# LSP Vim 插件设计文档

## 1. 目标与范围

用 Vim9script 从零实现一个 LSP（Language Server Protocol）Client，取代 `vim_back` 里错误较多的旧实现。

- **角色**：Client（Vim 编辑器端）
- **范围**：仅 **异步诊断** + **代码补全** 两项功能
- **定位编码**：始终 UTF-16（`position.character` 一律按 UTF-16 code unit 计数）
- **异步模型**：全程异步回调，无任何同步阻塞（含 `initialize` 握手）
- **配置**：用户自行配置 + 内置 `g:lsp_default_config` 提供多语言默认

不做（留待迭代 / 明确告知服务器不支持）：跳转定义、hover、引用、重命名、格式化、文档符号、codeAction、签名帮助、call/type hierarchy。

## 2. 关键技术结论（已确认）

1. **LSP stdio 传输是 Content-Length 头帧 + JSON-RPC 2.0**，与 ACP 的 newline-delimited 不同。Vim channel 的 `lsp` 模式（`in_mode`/`out_mode`）原生处理 Content-Length 分帧，无需手写缓冲。
2. **异步分层**（Vim channel 模型）：
   - **请求**（有 id，如 `initialize`、`textDocument/completion`）：`ch_sendexpr(channel, {method, params}, {callback})`，Vim 自动加 id，响应到 callback。**返回值是 `{id: <number>}`**（内部生成的请求 id），可用于发 `$/cancelRequest` 取消。
   - **通知**（无 id，如 `initialized`、`didOpen`、`didChange`、`didSave`、`didClose`、`didChangeConfiguration`）：`ch_sendexpr(channel, {method, params})`（不带 callback）。
   - **取消**：`ch_sendexpr(channel, {method: '$/cancelRequest', params: {id: <请求id>}})`（通知，无 callback）。
   - **服务器推送**（如 `textDocument/publishDiagnostics`、`window/logMessage`）：由 `out_cb` 接收并分发。
3. **补全的异步矛盾**：`complete()` 是同步函数，但 LSP 补全是异步的。解法：自动触发时发异步请求，响应在 callback 里 `timer_start(0, ...)` 二次调用 `complete()` 弹出菜单（方案 A）。
4. **Vim 9.2 原生 `'autocomplete'` 会干扰**：`init.vim` 全局开启了 `set autocomplete`，它会在 insert 模式自动调 omnifunc 弹窗。因此 **LSP 激活的 buffer 必须 `setlocal noautocomplete`**，由插件自己控制触发。

## 3. 文件布局与组件

```
pack/lattetao/opt/lsp/
├── plugin/lsp.vim          # 入口：配置默认值、autocmd 注册、highlight/sign/prop 初始化
└── autoload/lsp/
    ├── util.vim            # 纯函数：UTF-16 换算、uri/path、position 构造
    ├── server.vim          # 传输层 + 生命周期 + 文档同步 + 消息分发
    ├── diagnostic.vim      # 诊断存储 + 渲染（sign + virtual text + 高亮）
    └── complete.vim        # 异步补全
```

逻辑组件职责边界：

| 文件 | 职责 | 关键导出函数 |
|------|------|------|
| `util.vim` | 无状态纯函数 | `ByteToUtf16`、`Utf16ToByte`、`PathToUri`、`UriToPath`、`FsRoot`、`ApplyEdits` |
| `server.vim` | job 启动、initialize 回调链、文档同步、out_cb 分发 | `OpenBuf`、`CloseBuf`、`SaveBuf`、`Flush`、`OnData` |
| `diagnostic.vim` | 诊断渲染（推送即渲染）sign/vtext/prop | `Update` |
| `complete.vim` | 防抖触发、异步请求、二次 complete() | `Trigger` |

## 4. 配置模型

两个全局变量（`plugin/lsp.vim` 定义默认值，用户 vimrc 可覆盖/扩展）：

```vim
# 内置默认（多语言）：filetype -> {cmd, root_patterns, settings}
g:lsp_default_config = {
  go:         { cmd: ['gopls'],                    root_patterns: ['go.mod', '.git'],           settings: {} },
  c:          { cmd: ['clangd'],                   root_patterns: ['compile_commands.json', '.git', 'CMakeLists.txt'], settings: {} },
  cpp:        { cmd: ['clangd'],                   root_patterns: ['compile_commands.json', '.git', 'CMakeLists.txt'], settings: {} },
  python:     { cmd: ['basedpyright-langserver', '--stdio'], root_patterns: ['pyproject.toml', 'pyrightconfig.json', '.venv', '.git'], settings: {} },
  javascript: { cmd: ['typescript-language-server', '--stdio'], root_patterns: ['package.json', '.git'], settings: {} },
  typescript: { cmd: ['typescript-language-server', '--stdio'], root_patterns: ['package.json', '.git'], settings: {} },
  lua:        { cmd: ['lua-language-server'],      root_patterns: ['.luarc.json', '.git'],      settings: {} },
  rust:       { cmd: ['rust-analyzer'],            root_patterns: ['Cargo.toml', '.git'],       settings: {} },
}

# 合并后生效：用户可整体替换或 extend() 增加/覆盖 filetype
# 注意：合并必须在【运行时】做（server 首次启动时），而非 plugin 加载时，
# 否则用户在 vimrc 中 packadd 之后才定义的 g:lsp_servers 会丢失。
def Servers(): dict<any>
  var user = get(g:, 'lsp_servers', {})
  return empty(user) ? copy(g:lsp_default_config)
        \             : extend(copy(g:lsp_default_config), user)
enddef
```

运行时 server 对象（script-local 嵌套 `dict<any>`，key = filetype -> root_dir，**一个 root 一个 server 进程**）：

```
servers[filetype][root_dir] = {
  job, channel, root_dir, cmd, settings,
  ready: bool, capabilities: dict<any>, pending: list<number>
}
```

## 5. 传输层（RPC）

- **启动**：`job_start(cmd, {in_mode: 'lsp', out_mode: 'lsp', err_mode: 'nl', out_cb, err_cb, exit_cb})`
- **编码/解码**：`ch_sendexpr` 自动 JSON 序列化并加 Content-Length 帧；`out_cb(ch, msg)` 收到已解码的 `dict<any>`。
- **请求**（有 callback）：`ch_sendexpr(channel, {method, params}, {callback: (ch, msg) => ...})`
- **通知**（无 callback）：`ch_sendexpr(channel, {method, params})`
- **out_cb 分发**：`msg.method == 'textDocument/publishDiagnostics'` → `diagnostic#Update`；`window/logMessage`/`window/showMessage` → 日志；其余 → 日志。

## 6. 生命周期（全程异步回调链，一个 root 一个 server）

`BufNewFile,BufReadPost` → `server#OpenBuf(bufnr)`：

1. `ft = getbufvar(bufnr, '&filetype')`，`Servers()` 无此 ft 则返回。
2. `root = FsRoot(cfg.root_patterns, filepath)` 求根目录。
3. `server = servers[ft][root]`；不存在或 `job_status(server.job) != 'run'` → `job_start` + 发 `initialize`（单根，`workspaceFolders: [{uri, name}]`，带 callback）。
4. `initialize` 回调：校验 `result.capabilities`，保存 `server.capabilities` → 发 `initialized` → `didChangeConfiguration` → `ready = true` → `DrainPending(server)`（逐个 `didOpen` 排队 buffer）。
5. `didOpen`（幂等，`b:did_open` 守卫）：`server.ready` 则立即，否则 `add(server.pending, bufnr)` 排队。
6. 激活 buffer 副作用：`setlocal noautocomplete`。

`BufUnload` → `didClose`（`b:did_open` 置回 false）；`BufWritePost` → `didSave`；文档变更 → `Flush()`（带防抖）全文 `didChange`。

**存活策略**：server 启动后一直存活，不做引用计数、不主动 stop；`VimLeavePre` 统一停所有 job；job 自身 crash 由 `exit_cb` 置 `ready = false`，下次 OpenBuf 检测 `job_status != 'run'` 重启。

## 7. 文档同步

- **仅全文同步**（`TextDocumentSyncKind.Full`，`change = 1`）：`didChange` 的 `contentChanges` 只发 `[{text: 全文}]`，不做增量 diff。
- `Flush(bufnr)`：取当前 `getbufline()` 拼全文 → 发 `didChange`（`version = changedtick`，`contentChanges: [{text}]`）。
- **防抖（双阈值）**：`TextChanged,TextChangedI` 触发 `Flush` 时——
  1. 50ms 无新输入（时间窗）→ Flush；
  2. `changedtick` 差值 > 3（累积修改）→ 立即 Flush。
  实现：script-local 记录上次 Flush 的 `changedtick` + 防抖 timer；每次文本变更比较差值，超阈值立即发并重置 timer，否则重置 50ms timer 到期发。
- 同步是诊断/补全的前置依赖，必须保留。
- 说明：即便服务器声明 `textDocumentSync.change = 2`（增量），客户端也降级发全文（gopls/clangd/pyright 均兼容全文内容）。

## 8. 编码转换（UTF-16 位置 + URI 路径）

所有出站 position 的 `character` 字段 = UTF-16 code unit 偏移；所有入站 range 先转回字节偏移再定位。

Vim 相关 API（0-based）：`charidx(str, byte)` 字节→字符索引、`byteidx(str, char)` 字符→字节索引、`strgetchar(str, char)` 字符→码点、`strchars(str)` 字符数。

```vim
# 字节偏移 -> UTF-16 code unit 偏移
export def ByteToUtf16(line: string, byte: number): number
  var char = charidx(line, byte)
  var u: number = 0
  for i in range(char)
    u += strgetchar(line, i) > 0xffff ? 2 : 1
  endfor
  return u
enddef

# UTF-16 code unit 偏移 -> 字节偏移
export def Utf16ToByte(line: string, utf16: number): number
  var u: number = 0
  var i: number = 0
  var n: number = strchars(line)
  while i < n && u < utf16
    u += strgetchar(line, i) > 0xffff ? 2 : 1
    i += 1
  endwhile
  return byteidx(line, i)
enddef
```

Position 构造（Vim 1-based → LSP 0-based）：`{line: lnum - 1, character: ByteToUtf16(getline(lnum), col - 1)}`。

### URI 编码（参考 Neovim `runtime/lua/vim/uri.lua`）

- **编码规则**：RFC 3986 保留字符集 `A-Za-z0-9-._~!$&'()*+,;=:@/`（含 `/`）**不编码**，其余字符逐字节 `%XX`。
- **逐字节**：Vim 字符串是 UTF-8（非字节序列），用 `str2blob([char])`（接受 List）取字符的 UTF-8 字节逐个 `%XX`（中文 `我` → `%E6%88%91`），**不能用 `char2nr()`（那是码点）或 `iconv(latin1)`（毁中文）**。
- **解码**：`%XX` 逐字节解码进 blob，再 `blob2str()` 还原 UTF-8（`blob2str` 返回 List，需 `join(..., '')`）。

```vim
var uri_reserved = 'A-Za-z0-9\-._~!$&''()*+,;=:@/'

export def UriEncode(path: string): string
  var out = ''
  for c in split(path, '\zs')
    if c =~# '[' .. uri_reserved .. ']'
      out ..= c
    else
      for b in str2blob([c])
        out ..= printf('%%%02X', b)
      endfor
    endif
  endfor
  return out
enddef

export def UriDecode(uri: string): string
  # 先切掉 scheme/fragment（'file://'、'#' 之后），再逐字节解码 %XX -> blob -> blob2str
  ...
enddef

export def PathToUri(path: string): string
  return 'file://' .. UriEncode(path)
enddef

export def UriToPath(uri: string): string
  return UriDecode(substitute(uri, '^file://', '', ''))
enddef
```

- `%` 字符本身不在保留集，编码成 `%25`，解码 `%25`→`%`，对称无损。

## 9. 异步诊断

- **推送即渲染**（无需 autocmd/定时器）：`publishDiagnostics` 到达（channel 回调，安全时刻）→ `diagnostic#Update(params)` 直接渲染。
- **Update 流程**：
  1. 写入 `b:lsp_diagnostics`（`list<dict<any>>`）+ `b:lsp_diag_version`。
  2. 校验 `version >= changedtick`，过期诊断（针对旧文档的）直接丢弃不渲染。
  3. 先清除该 buffer 旧诊断标记（`sign_unplace('LspDiag', {buffer})` + `prop_remove`），再按当前诊断重绘（幂等）。
- **渲染三件套**：
  - `sign_place(id, 'LspDiag', <severity sign>, bufnr, {lnum, priority})` —— id 用 script-local 自增计数器，确保唯一（旧实现的 bug 是用 severity 作 id 导致同级别覆盖）。
  - 行内高亮：`prop_add`（`type` 按 severity，覆盖 range）。
  - 行尾消息：`prop_add(..., text: ' <-- ' .. message, text_align: 'after')`（virtual text）。
- severity 映射：1=Error、2=Warning、3=Info、4=Hint，各自有 sign text（E/W/I/H）、inline prop 高亮、virtual text prop。
- 初始化（plugin/lsp.vim）：`sign_define`、`prop_type_add`、`highlight` 一次完成，用 `highlight default link`。

## 10. 异步补全（autocmd 自动触发 + 方案 A）

触发链（`InsertCharPre` 触发，250ms 防抖延后，解决插入前 position 偏移 + 让 Flush 先同步）：

1. `InsertCharPre` → 保存 `v:char` → 重置 250ms 防抖 timer。
2. timer 到期（字符已插入、防抖的 Flush 已发出）：
   a. 强制 `Flush(bufnr)`（立即全文 didChange，先发，channel FIFO 保证先到）；
   b. 若有 in-flight 补全请求，先发 `$/cancelRequest` 取消旧 id；
   c. 发 `textDocument/completion`（带 callback），保存返回 `{id}` 到 `in_flight_id`；
   d. 快照补全上下文 `s:ctx = {bufnr, winid, lnum, col, prefix}`。
3. 响应 callback：
   - 校验 `resp.id == in_flight_id`，过期丢弃；
   - 校验 context：`mode() =~ '^i'` 且 `bufnr`/`winid`/`lnum`/`col` 全等，否则丢弃；
   - normalize 成 `complete()` 的 `{word, abbr, kind, menu, info, ...}` → `timer_start(0)` 里 `complete(startcol, items)` 弹窗。

- **triggerKind**：1=Invoked（默认）、2=TriggerCharacter（`v:char` 命中 `completionProvider.triggerCharacters`）、3=TriggerForIncompleteCompletions（上一轮 `isIncomplete` 且同前缀）。
- **startcol**：取 `textEdit.range.start`（若存在）转字节列作为 `complete()` 的 startcol，而非简单用 prefix 起始，避免 `std::str` → `std::string` 这类 range 覆盖导致重复；无 `textEdit` 时用 prefix 起始字节列。
- **normalize**：`word` 取 `textEdit.newText ?? insertText ?? label`；`snippetSupport: false`，含 `$0`/`${}` 占位符的项丢弃或按纯文本；`user_data` 携带 `additionalTextEdits` 与 `preselect`。
- **CompleteDone 后处理（post textedit）**：autocmd `CompleteDone` → `complete#OnDone()`，从 `v:completed_item.user_data` 取 `additionalTextEdits`（自动插 import/`#include`），`util#ApplyEdits(bufnr, edits)` 应用。`ApplyEdits`：UTF-16 range → 字节，按位置**降序**逐条 `deletebufline`+`appendbufline`，`undojoin` 合并；**不保存/恢复 marks**（Vim 自动调整 mark，手动 `setpos` 反而错位）。不支持 `command`（`executeCommand` 已砍）。

## 11. capabilities（最小化，明确告知不支持）

只声明实现的功能，未声明的即告知服务器"客户端不支持"：

```
general:      { positionEncodings: ['utf-16'] }
workspace:    { workspaceFolders: true }
textDocument: {
  synchronization: { dynamicRegistration: false, willSave: false, willSaveWaitUntil: false, didSave: false },
  completion:      { completionItem: { snippetSupport: false, deprecatedSupport: true } },
  publishDiagnostics: { relatedInformation: false }
}
```

不声明 definition / hover / references / rename / formatting / documentSymbol / codeAction / signatureHelp / typeDefinition / implementation / declaration / callHierarchy / typeHierarchy。

**workspace 安全边界**：不声明 `workspace.workspaceEdit` / `workspace.applyEdit`，因此服务器不会（按协议约定也不应）发 `workspace/applyEdit` 请求来修改 workspace。诊断是只读推送，补全由客户端插入 buffer，均不涉及服务器改文件。`out_cb` 分发时对任何 server→client 的请求（带 id 无匹配，如 `workspace/applyEdit`）一律忽略，不执行、不落地任何文件修改。

## 12. autocmd 汇总（plugin/lsp.vim 注册）

| 事件 | 处理 |
|------|------|
| `BufNewFile,BufReadPost` | `server#OpenBuf()`（启动 + didOpen + `setlocal noautocomplete`） |
| `BufUnload` | `server#CloseBuf()`（didClose） |
| `BufWritePost` | `server#SaveBuf()`（didSave） |
| `TextChanged,TextChangedI` | `server#Flush()`（全文 didChange，双阈值防抖：50ms / changedtick>3） |
| `InsertCharPre` | `complete#Trigger(v:char)`（250ms 防抖，用 `v:char` 判断 triggerKind） |
| `CompleteDone` | `complete#OnDone()`（应用 additionalTextEdits，如插入 import/头文件） |
| `VimLeavePre` | 停所有 job |

## 13. 错误处理与退出清理

- `exit_cb`：日志 + 置 `ready = false`、清 `channel/job`（`server` 对象保留供重连）。
- `err_cb`：stderr 写日志，不打扰用户。
- 日志：`g:lsp_logfile`（默认 `/tmp/lsp.log`）。
- 发送前检查 `job_status() == 'run'` 与 `ready`，否则跳过。
- `initialize` 回调校验失败 → 日志 + 不置 ready。
- `VimLeavePre`：遍历 `servers` 所有 server 逐个 `job_stop()`（存活策略 B：不主动 stop，仅退出时统一停）。

## 14. 测试

- 每文件语法自检：`vim -Nu NONE -n -es -c 'source <file>' -c 'qa!'` 无报错。
- 端到端：打开 go/python 文件 → 确认 server 启动（日志）→ 打字触发补全弹出 → 故意写错看诊断 sign/vtext/高亮 → 保存后诊断刷新 → 关闭 buffer 后 server 仍存活，`VimLeavePre` 统一停。
- UTF-16：构造含 emoji 的行，验证 position 与诊断 range 定位不偏移。
