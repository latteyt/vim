# ACP Vim 插件实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 逐任务实现，步骤用 checkbox（`- [ ]`）跟踪。

**Goal:** 用 Vim9script 实现 ACP v1 Client 插件，让 Vim 连接 opencode 进行 AI 对话。

**Architecture:** 单 `autoload/acp.vim`（script-local 状态 + 函数前缀分区）+ `plugin/acp.vim`（配置/命令/映射）。传输用 `nl` channel 模式 + 内置 `json_encode`/`json_decode` + 手动 id 匹配，全异步回调模型。

**Tech Stack:** Vim9script、`job_start()`/channel（`nl` 模式）、`json_encode`/`json_decode`、opencode `acp` 子命令。

**Spec:** `pack/lattetao/opt/acp/DESIGN.md`

## Global Constraints

- Vim9script：文件首行 `vim9script`；autoload 函数用 `export def`；状态用 script-local `var`
- 传输：`in_mode/out_mode/err_mode = 'nl'`，发送 `json_encode(dict) .. "\n"`，接收 `json_decode(msg)`
- 属性命名 `camelCase`，判别字段 `snake_case`（如 `sessionUpdate`、`stopReason`）
- 文件路径绝对、行号 1-based
- agent 启动命令默认 `['opencode', 'acp']`
- 每完成一个任务：语法自检 `vim -Nu NONE -n -es -c 'source <file>' -c 'qa!'` 无报错，再提交
- 不引入新依赖、不新建无谓文件

---

### Task 1: 骨架 + RPC 传输层

**Files:**
- Create: `pack/lattetao/opt/acp/autoload/acp.vim`

**Interfaces:**
- Produces（后续任务依赖）：
  - `export def Rpc_Send(method: string, params: dict<any>, callback: func = v:null): void` — 发请求并登记回调
  - `export def Rpc_Reply(id: any, result: any): void` — 回写响应
  - `export def Rpc_ReplyError(id: any, code: number, message: string): void` — 回写错误
  - script-local `var channel: channel`、`var pending_calls: dict<func>`、`var next_id: number`

- [ ] **Step 1: 写启动与回调骨架 + 消息分类**

```vim
vim9script

var channel: channel = v:null
var job: job = v:null
var pending_calls: dict<func> = {}
var next_id: number = 1

def OnData(ch: channel, msg: string)
  var decoded: any = null
  try
    decoded = json_decode(msg)
  catch
    return
  endtry
  if type(decoded) != v:t_dict
    return
  endif
  # 有 method 且有 id → agent 调 client（请求）；无 method 有 id → 响应；仅 method → 通知
  if has_key(decoded, 'method') && has_key(decoded, 'id')
    # Task 5/6 分发
  elseif has_key(decoded, 'id')
    var cb = remove(pending_calls, decoded.id)
    if cb != v:null
      cb(decoded)
    endif
  elseif has_key(decoded, 'method')
    # session/update → Task 3 分发
  endif
enddef

def OnStderr(ch: channel, msg: string)
  if exists('g:acp_logfile')
    writefile([msg], g:acp_logfile, 'a')
  endif
enddef

def OnExit(ch: channel, status: number)
  pending_calls = {}
  # Task 2 状态置 disconnected
enddef
```

- [ ] **Step 2: 写 Rpc_Send / Rpc_Reply / Rpc_ReplyError**

```vim
export def Rpc_Send(method: string, params: dict<any>, callback: func = v:null): void
  var req = { jsonrpc: '2.0', id: next_id, method: method, params: params }
  next_id += 1
  if callback != v:null
    pending_calls[req.id] = callback
  endif
  ch_sendraw(channel, json_encode(req) .. "\n")
enddef

export def Rpc_Reply(id: any, result: any): void
  ch_sendraw(channel, json_encode({ jsonrpc: '2.0', id: id, result: result }) .. "\n")
enddef

export def Rpc_ReplyError(id: any, code: number, message: string): void
  ch_sendraw(channel, json_encode({ jsonrpc: '2.0', id: id, error: { code: code, message: message } }) .. "\n")
enddef

export def Rpc_Notify(method: string, params: dict<any>): void
  ch_sendraw(channel, json_encode({ jsonrpc: '2.0', method: method, params: params }) .. "\n")
enddef
```

- [ ] **Step 3: 语法自检**

Run: `vim -Nu NONE -n -es -c 'source pack/lattetao/opt/acp/autoload/acp.vim' -c 'qa!'`
Expected: 无报错退出。

- [ ] **Step 4: Commit**

```bash
git add pack/lattetao/opt/acp/autoload/acp.vim
git commit -m "acp: add rpc transport layer"
```

---

### Task 2: 连接启动 + 协议状态机（initialize/session-new）

**Files:**
- Modify: `pack/lattetao/opt/acp/autoload/acp.vim`

**Interfaces:**
- Consumes: `Rpc_Send`、`Rpc_Reply`（Task 1）
- Produces:
  - `export def Session_Open(): void` — 启动 job + initialize + session/new
  - script-local `var state: string`、`var session_id: string`、`var agent_caps: dict<any>`

- [ ] **Step 1: 加状态变量与 job 启动**

```vim
var state: string = 'disconnected'
var session_id: string = ''
var agent_caps: dict<any> = {}

export def Session_Open(): void
  if job != v:null && job_status(job) == 'run'
    return
  endif
  var cwd = exists('g:acp_cwd') && g:acp_cwd != '' ? g:acp_cwd : getcwd()
  var cmd = exists('g:acp_cmd') ? g:acp_cmd : ['opencode', 'acp']
  var opts = {
    in_mode: 'nl', out_mode: 'nl', err_mode: 'nl',
    out_cb: OnData, err_cb: OnStderr, exit_cb: OnExit,
  }
  job = job_start(cmd + ['--cwd', cwd], opts)
  channel = job_getchannel(job)
  state = 'initializing'
  Init_()
enddef
```

- [ ] **Step 2: initialize + session/new 回调链**

```vim
def Init_(): void
  Rpc_Send('initialize', {
    protocolVersion: 1,
    clientCapabilities: { fs: { readTextFile: true, writeTextFile: true } },
    clientInfo: { name: 'acp-vim', title: 'ACP Vim', version: '0.1.0' },
  }, (resp) => OnInitResp(resp))
enddef

def OnInitResp(resp: dict<any>): void
  if has_key(resp, 'error') || resp.result.protocolVersion != 1
    state = 'disconnected'
    return
  endif
  agent_caps = get(resp.result, 'agentCapabilities', {})
  state = 'newing'
  Rpc_Send('session/new', {
    cwd: exists('g:acp_cwd') && g:acp_cwd != '' ? g:acp_cwd : getcwd(),
    mcpServers: [],
  }, (resp2) => OnNewResp(resp2))
enddef

def OnNewResp(resp: dict<any>): void
  if has_key(resp, 'error')
    state = 'disconnected'
    return
  endif
  session_id = resp.result.sessionId
  state = 'ready'
enddef
```

- [ ] **Step 3: exit_cb 完善状态重置**

在 `OnExit` 中追加：`state = 'disconnected'`、`session_id = ''`。

- [ ] **Step 4: 语法自检**（同 Task 1 Step 3 命令，下同）

- [ ] **Step 5: Commit**

```bash
git add pack/lattetao/opt/acp/autoload/acp.vim
git commit -m "acp: add connection and protocol state machine"
```

---

### Task 3: prompt 轮次 + session/update 分发

**Files:**
- Modify: `pack/lattetao/opt/acp/autoload/acp.vim`

**Interfaces:**
- Consumes: `Rpc_Send`、`Rpc_Notify`、`session_id`、`state`
- Produces:
  - `export def Session_Prompt(text: string): void` — 发送 prompt 并回显
  - `export def Session_Cancel(): void` — 发 `session/cancel`
  - script-local `def OnUpdate(update: dict<any>): void` — 按 `sessionUpdate` 分发（Task 4 接 UI）

- [ ] **Step 1: Session_Prompt / Session_Cancel**

```vim
export def Session_Prompt(text: string): void
  if state != 'ready'
    return
  endif
  Ui_EchoUser(text)   # Task 4
  Rpc_Send('session/prompt', {
    sessionId: session_id,
    prompt: [{ type: 'text', text: text }],
  }, (resp) => OnPromptResp(resp))
enddef

export def Session_Cancel(): void
  if session_id != ''
    Rpc_Notify('session/cancel', { sessionId: session_id })
  endif
enddef

def OnPromptResp(resp: dict<any>): void
  # stopReason 已到，轮次结束；MVP 不额外渲染
enddef
```

- [ ] **Step 2: OnData 里接入通知分发**

在 `OnData` 的 `elseif has_key(decoded, 'method')` 分支调用 `OnNotification(decoded)`，并实现：

```vim
def OnNotification(msg: dict<any>): void
  if msg.method == 'session/update'
    OnUpdate(get(msg.params, 'update', {}))
  endif
enddef

def OnUpdate(update: dict<any>): void
  var kind = get(update, 'sessionUpdate', '')
  if kind == 'agent_message_chunk'
    Ui_AppendAgent(update)   # Task 4
  elseif kind == 'tool_call'
    Ui_AppendLine('[工具] ' .. get(update, 'title', ''))
    # 收集 locations 供 Task 6
  elseif kind == 'tool_call_update'
    Ui_AppendLine('[工具] ' .. get(update, 'title', '') .. ' -> ' .. get(update, 'status', ''))
  elseif kind == 'plan'
    for e in get(update, 'entries', [])
      Ui_AppendLine(get(e, 'priority', '') .. ': ' .. get(e, 'content', ''))
    endfor
  endif
enddef
```

- [ ] **Step 3: 语法自检**

- [ ] **Step 4: Commit**

```bash
git add pack/lattetao/opt/acp/autoload/acp.vim
git commit -m "acp: add prompt turn and session/update dispatch"
```

---

### Task 4: 对话 buffer 渲染（Ui_*）

**Files:**
- Modify: `pack/lattetao/opt/acp/autoload/acp.vim`

**Interfaces:**
- Consumes: `OnUpdate` 调用（Task 3）
- Produces:
  - `export def Ui_Open(): void` — 确保连接并打开 buffer
  - script-local `def Ui_AppendAgent(update: dict<any>): void`、`def Ui_AppendLine(text: string): void`、`def Ui_EchoUser(text: string): void`

- [ ] **Step 1: buffer 创建与追加**

```vim
def Ui_Buf(): number
  var bname = exists('g:acp_chat_bufname') ? g:acp_chat_bufname : 'acp://chat'
  var bnr = bufnr(bname, true)
  if bnr == -1
    bnr = bufadd(bname)
  endif
  setbufvar(bnr, '&buftype', 'nofile')
  setbufvar(bnr, '&buflisted', false)
  setbufvar(bnr, '&swapfile', false)
  setbufvar(bnr, '&undofile', false)
  setbufvar(bnr, '&modifiable', false)
  setbufvar(bnr, 'acp_chat', 1)
  return bnr
enddef

def Ui_AppendLine(text: string): void
  var bnr = Ui_Buf()
  appendbufline(bnr, '$', text)
  Ui_Scroll(bnr)
enddef

def Ui_AppendAgent(update: dict<any>): void
  var content = get(update, 'content', {})
  if get(content, 'type', '') == 'text'
    Ui_AppendLine(get(content, 'text', ''))
  endif
enddef

def Ui_EchoUser(text: string): void
  Ui_AppendLine('> ' .. text)
enddef

def Ui_Scroll(bnr: number): void
  var wins = win_findbuf(bnr)
  for w in wins
    win_execute(w, 'normal! G')
  endfor
enddef
```

- [ ] **Step 2: Ui_Open 打开 buffer**

```vim
export def Ui_Open(): void
  Session_Open()
  var bnr = Ui_Buf()
  if !bufloaded(bnr)
    bufload(bnr)
  endif
  if win_findbuf(bnr)->empty()
    execute 'sbuffer ' .. bnr
  endif
enddef
```

- [ ] **Step 3: 语法自检**

- [ ] **Step 4: Commit**

```bash
git add pack/lattetao/opt/acp/autoload/acp.vim
git commit -m "acp: add chat buffer rendering"
```

---

### Task 5: fs 读写（Fs_Read / Fs_Write）

**Files:**
- Modify: `pack/lattetao/opt/acp/autoload/acp.vim`

**Interfaces:**
- Consumes: `Rpc_Reply`、`Rpc_ReplyError`（Task 1）
- Produces: `def Fs_Read(id: any, params: dict<any>): void`、`def Fs_Write(id: any, params: dict<any>): void`

- [ ] **Step 1: OnData 请求分支分发 fs**

在 `OnData` 的 `has_key(decoded, 'method') && has_key(decoded, 'id')` 分支：

```vim
if decoded.method == 'fs/read_text_file'
  Fs_Read(decoded.id, decoded.params)
elseif decoded.method == 'fs/write_text_file'
  Fs_Write(decoded.id, decoded.params)
elseif decoded.method == 'session/request_permission'
  Perm_Decide(decoded.id, decoded.params)   # Task 6
endif
```

- [ ] **Step 2: Fs_Read（buffer 优先，含未保存改动）**

```vim
def Fs_Read(id: any, params: dict<any>): void
  var path = get(params, 'path', '')
  var line = get(params, 'line', 1)
  var limit = get(params, 'limit', -1)
  var lines: list<string> = []
  var bnr = bufnr(path)
  if bnr != -1 && bufloaded(bnr)
    var last = limit > 0 ? line + limit - 1 : '$'
    lines = getbufline(bnr, line, last)
  else
    lines = readfile(path)
    if line > 1 || limit > 0
      lines = lines[(line - 1) : (limit > 0 ? line + limit - 2 : -1)]
    endif
  endif
  Rpc_Reply(id, { content: join(lines, "\n") .. (empty(lines) ? '' : "\n") })
enddef
```

- [ ] **Step 3: Fs_Write（buffer 优先 + 落盘）**

```vim
def Fs_Write(id: any, params: dict<any>): void
  var path = get(params, 'path', '')
  var content = get(params, 'content', '')
  var lines = split(content, "\n", true)
  var bnr = bufnr(path)
  if bnr != -1 && bufloaded(bnr)
    setbufvar(bnr, '&modifiable', true)
    setbufline(bnr, 1, lines)
    execute 'buffer ' .. bnr
    silent! write
    setbufvar(bnr, '&modifiable', false)
  else
    var dir = fnamemodify(path, ':h')
    if !isdirectory(dir)
      mkdir(dir, 'p')
    endif
    writefile(lines, path)
  endif
  Rpc_Reply(id, v:null)
enddef
```

- [ ] **Step 4: 语法自检**

- [ ] **Step 5: Commit**

```bash
git add pack/lattetao/opt/acp/autoload/acp.vim
git commit -m "acp: add fs read/write with buffer-first strategy"
```

---

### Task 6: 权限响应（Perm_Decide）

**Files:**
- Modify: `pack/lattetao/opt/acp/autoload/acp.vim`

**Interfaces:**
- Consumes: `Rpc_Reply`；`tool_call` 通知里的 `locations`（Task 3 已留收集点）
- Produces: `def Perm_Decide(id: any, params: dict<any>): void`；script-local `var tool_locations: dict<list<dict<any>>>`

- [ ] **Step 1: 收集 locations**

在 Task 3 的 `OnUpdate` 里 `kind == 'tool_call'` 分支追加：

```vim
var locs = get(update, 'locations', [])
if !empty(locs)
  tool_locations[get(update, 'toolCallId', '')] = locs
endif
```

声明 `var tool_locations: dict<list<dict<any>>> = {}`。

- [ ] **Step 2: Perm_Decide**

```vim
def Perm_Decide(id: any, params: dict<any>): void
  var toolCall = get(params, 'toolCall', {})
  var tc_id = get(toolCall, 'toolCallId', '')
  var locs = get(toolCall, 'locations', [])
  if empty(locs) && has_key(tool_locations, tc_id)
    locs = tool_locations[tc_id]
  endif
  var in_buf = false
  for l in locs
    var p = get(l, 'path', '')
    if p != '' && bufnr(p) != -1 && bufloaded(bufnr(p))
      in_buf = true
      break
    endif
  endfor
  var want = in_buf ? 'allow_once' : 'reject_once'
  var option_id = ''
  for o in get(params, 'options', [])
    if get(o, 'kind', '') == want
      option_id = get(o, 'optionId', '')
      break
    endif
  endfor
  if option_id != ''
    Rpc_Reply(id, { outcome: { outcome: 'selected', optionId: option_id } })
  else
    Rpc_Reply(id, { outcome: { outcome: 'cancelled' } })
  endif
enddef
```

- [ ] **Step 3: 语法自检**

- [ ] **Step 4: Commit**

```bash
git add pack/lattetao/opt/acp/autoload/acp.vim
git commit -m "acp: add permission handling with buffer-first allow"
```

---

### Task 7: plugin 入口（配置/命令/映射/清理）

**Files:**
- Create: `pack/lattetao/opt/acp/plugin/acp.vim`

**Interfaces:**
- Consumes: `Session_Open`、`Session_Prompt`、`Session_Cancel`、`Ui_Open`（autoload `acp#`）

- [ ] **Step 1: plugin/acp.vim 完整内容**

```vim
vim9script
if exists('g:loaded_acp')
  finish
endif
g:loaded_acp = v:true

def g:AcpOpen(): void
  acp#Ui_Open()
enddef
def g:AcpPrompt(text: string): void
  acp#Session_Prompt(text)
enddef
def g:AcpCancel(): void
  acp#Session_Cancel()
enddef

command! AcpOpen call g:AcpOpen()
command! -nargs=+ AcpPrompt call g:AcpPrompt(<q-args>)
command! AcpCancel call g:AcpCancel()

if get(g:, 'acp_map', 1)
  nnoremap <leader>ao :AcpOpen<CR>
  nnoremap <leader>ap :AcpPrompt<Space>
  nnoremap <leader>ac :AcpCancel<CR>
endif

augroup acp_vim
  autocmd!
  autocmd VimLeave * if exists('g:acp_job') | call job_stop(g:acp_job) | endif
augroup END
```

> 注：`job`/`channel` 是 autoload 的 script-local `var`，`VimLeave` 清理需要 autoload 暴露 `acp#Close()`；若 Step 1 无法直接引用，改为在 autoload 加 `export def Close(): void` 并在此 autocmd 调用 `acp#Close()`。

- [ ] **Step 2: autoload 补 Close()**

在 `acp.vim` 末尾加：

```vim
export def Close(): void
  if job != v:null && job_status(job) == 'run'
    job_stop(job)
  endif
enddef
```

- [ ] **Step 3: 语法自检（两个文件）**

Run: `vim -Nu NONE -n -es -c 'set rtp+=pack/lattetao/opt/acp' -c 'source pack/lattetao/opt/acp/plugin/acp.vim' -c 'qa!'`

- [ ] **Step 4: Commit**

```bash
git add pack/lattetao/opt/acp/plugin/acp.vim pack/lattetao/opt/acp/autoload/acp.vim
git commit -m "acp: add plugin entry point with commands and mappings"
```

---

### Task 8: 端到端验证

**Files:**
- Modify: `pack/lattetao/opt/acp/autoload/test_acp.vim`（改为正式协议冒烟脚本或删除）

- [ ] **Step 1: 端到端手动验证**

在 Vim 中（已 `packadd acp`）：
1. `:AcpOpen` — 出现对话 buffer
2. `:AcpPrompt 说一句你好` — buffer 出现 `> 说一句你好`，随后流式出现 agent 回复
3. 生成中按 `:AcpCancel` — 中断，收到 `stopReason == 'cancelled'`
4. 打开某文件 → 让 agent 读该文件（验证含未保存改动）
5. 让 agent 改该文件 → 验证 buffer 同步

- [ ] **Step 2: 清理 test_acp.vim**

删除 `autoload/test_acp.vim`（验证脚本已使命完成），或改名为正式冒烟测试脚本并保留。默认删除。

```bash
git rm pack/lattetao/opt/acp/autoload/test_acp.vim
```

- [ ] **Step 3: 在 init.vim 加 packadd**

Modify: `init.vim`（在 `packadd! fuzzyfinder` 附近加 `packadd! acp`）

- [ ] **Step 4: Commit**

```bash
git add pack/lattetao/opt/acp/autoload/test_acp.vim init.vim
git commit -m "acp: end-to-end verification and enable plugin"
```

---

## Self-Review 记录

- **Spec 覆盖**：Task 1↔DESIGN §4（传输层）、Task 2↔§5（状态机）、Task 3↔§5 prompt 轮次 + §6 session/update 分发、Task 4↔§6 buffer 渲染、Task 5↔§7 fs、Task 6↔§7 权限、Task 7↔§8 配置/命令/映射、Task 8↔§10 测试。全部覆盖。
- **占位符**：无 TBD/TODO。
- **类型一致性**：`Rpc_Send(method, params, callback)`、`session_id`、`state`、`tool_locations` 各任务命名一致。
