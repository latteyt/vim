# ACP Vim 插件设计文档

## 1. 目标与范围

用 Vim9script 实现一个 ACP（Agent Client Protocol）v1 的 **Client** 端插件，让 Vim 作为编辑器连接外部 AI 编码代理（opencode），在 Vim 内进行 AI 对话。

- **角色**：Client（Vim 编辑器端）
- **目标 Agent**：opencode（启动命令 `opencode acp`，版本 1.18.20，仅支持 ACP v1）
- **MVP 范围**：通信层 + 基础对话（单会话）
- **UI**：专用 buffer + 命令行输入
- **渲染**：全部扁平文本
- **fs 策略**：已打开 buffer 的文件通过 Vim 读写
- **权限策略**：目标文件在 buffer 内自动同意，否则拒绝

不做（留待迭代）：多会话、会话管理（list/load/resume/close）、多行浮动输入框、结构化渲染（tool_use/diff 高亮）、终端生命周期（`terminal/*`）。

## 2. 关键技术结论（已验证）

ACP 的 stdio 传输是 **newline-delimited JSON**（每条消息一行、不含内嵌换行），**不是** LSP 的 Content-Length 头帧。

Vim channel 模式对比：

| 模式 | 分帧/格式 | 匹配 ACP |
|------|-----------|---------|
| `lsp` | Content-Length 头 + JSON-RPC 2.0 | 否 |
| `json` | Vim 私有 `[id, expr]` 数组 | 否 |
| `nl` | `\n` 分隔，回调收完整行字符串 | **是** |

因此采用：**`nl` 模式 + Vim 内置 `json_encode()`/`json_decode()` + 手动 id 匹配**。

已用 `test_acp.vim` 验证：`ch_evalraw`（同步）与 `ch_sendraw` + `out_cb`（异步）均能正确收发 JSON-RPC 消息，`initialize` 响应返回 `protocolVersion:1` 及 opencode 能力集。

## 3. 文件布局与组件

- `plugin/acp.vim` — 入口：`g:loaded_acp` 守卫、配置项默认值、命令、默认映射
- `autoload/acp.vim` — 全部实现，函数按职责前缀分区

逻辑组件（同一文件内，职责边界清晰）：

| 前缀 | 职责 | 关键函数 |
|------|------|---------|
| `Rpc_*` | JSON-RPC 传输：编码发送、消息分类分发、id 匹配、channel 回调 | `Rpc_Send`、`Rpc_OnData`、`Rpc_OnExit`、`Rpc_Request` |
| `Session_*` | ACP 协议状态机：握手、会话、prompt 轮次 | `Session_Open`、`Session_New`、`Session_Prompt`、`Session_Cancel` |
| `Fs_*` | 响应 agent 的 fs 读写请求（buffer 优先） | `Fs_Read`、`Fs_Write` |
| `Perm_*` | 响应权限请求（buffer 内自动同意） | `Perm_Decide` |
| `Ui_*` | 对话 buffer 渲染、命令实现 | `Ui_Open`、`Ui_Append`、`Ui_Reply` |

script-local 状态（`autoload/acp.vim` 内共享 `var`）：
`channel`、`job`、`session_id`、`protocol_version`、`pending_calls`（`dict<func>` 按 id 匹配）、`agent_caps`、`client_caps`、`state`（状态机）、`tool_locations`（toolCallId → locations 映射）。

## 4. RPC 传输层

- **启动**：`job_start(['opencode', 'acp', '--cwd', cwd])`，`out_mode/err_mode/in_mode = 'nl'`
- **分帧**：`nl` 模式原生按 `\n` 分帧，`out_cb(ch, msg)` 收到完整一行字符串（去换行），无需手写缓冲
- **解码**：`json_decode(msg)` 得 `dict<any>`
- **编码**：`ch_sendraw(channel, json_encode(dict) .. "\n")`
- **回调**：`out_cb`（收消息）、`err_cb`（stderr，默认忽略）、`exit_cb`（agent 退出清理）

消息分类（`json_decode` 后）：

| 条件 | 类型 | 处理 |
|------|------|------|
| 有 `method` 且有 `id` | 请求（agent→client 调用） | 分发到 Fs/Perm，回带 id 的响应 |
| 有 `id` 无 `method` | 响应 | 按 id 查 `pending_calls` 执行回调 |
| 有 `method` 无 `id` | 通知 | `session/update` → Ui 等 |

- **id 匹配**：`Rpc_Request(method, params, callback)` 用自增数字 id，登记 `pending_calls[id] = callback`，响应到达执行并删除。`nl` 模式不自动匹配 id，需自实现
- **错误响应**：agent 请求处理失败回 `{jsonrpc:'2.0', id, error:{code, message}}`

## 5. ACP 协议状态机

状态：`disconnected → initializing → newing → ready → prompting`（`state` 变量），防止乱序操作。

1. **启动**：`job_start`，登记回调
2. **initialize**（异步）：`{method:'initialize', params:{protocolVersion:1, clientCapabilities, clientInfo}}`，回调校验 `result.protocolVersion == 1`，保存 `agentCapabilities`
3. **session/new**（异步）：`{method:'session/new', params:{cwd, mcpServers:[]}}`，回调保存 `result.sessionId`
4. **ready** → 可 prompt

prompt 轮次：
1. `session/prompt` 请求，`params:{sessionId, prompt:[{type:'text', text}]}`
2. agent 流式推 `session/update` 通知（无 id）→ Ui 渲染
3. `:AcpCancel` → 发 `session/cancel` 通知（`params:{sessionId}`）
4. `session/prompt` 响应返回（含 `stopReason`）→ 轮次结束

`stopReason`：`end_turn`、`max_tokens`、`max_turn_requests`、`refusal`、`cancelled`。

## 6. 内容块渲染与 buffer 管理

对话 buffer：`bufname = g:acp_chat_bufname`（默认 `acp://chat`），`b:acp_chat = 1`，属性 `nobuflisted noswapfile noundofile nomodifiable`（用 `appendbufline()` 追加）。`:AcpOpen` 分屏打开，追加后滚到底部。

`session/update` 分发（`params.update.sessionUpdate` 判别）：

| `sessionUpdate` | 扁平渲染 |
|-----------------|---------|
| `agent_message_chunk` | `content.type == 'text'` 追加 `content.text`；否则忽略 |
| `tool_call` | 追加 `[工具] <title>` |
| `tool_call_update` | 追加 `[工具] <title> → <status>` |
| `plan` | 逐条 `<priority>: <content>` |
| `usage_update` / 其他 | 忽略 |

- 用户消息回显：发 prompt 时先追加用户角色标记 + 文本
- 分段：`agent_message_chunk` 直接连续追加；遇到 `tool_call`/`plan` 先换行再插标记
- 注意：`agent_message_chunk` 的 `content` 是**单个** content block；`tool_call_update` 的 `content` 是数组，按分支分别处理

## 7. fs 读写与权限响应

client 声明 `fs.readTextFile/writeTextFile: true` 后，agent 会把所有文件读写委托给 client。实现统一处理：已打开 buffer 走 buffer，未打开直接读写磁盘。

**`fs/read_text_file`**（`Fs_Read`，响应 `{result:{content}}`）：
- 已加载 buffer → `getbufline(buf, line, line+limit-1)`（含未保存改动）→ `join("\n")`
- 无 buffer → `readfile(path)` 按 `line`/`limit` 切片
- 失败回 error

**`fs/write_text_file`**（`Fs_Write`，响应 `{result:null}`）：
- 已加载 buffer → `setbufline(buf, 1, content_list)` 替换 + `:write` 保存
- 无 buffer → `writefile(content_list, path)`（父目录不存在则 `mkdir`）
- 失败回 error

**`session/request_permission`**（`Perm_Decide`）：
- 参数 `{sessionId, toolCall, options}`，`options` 含 `kind ∈ {allow_once, reject_once, allow_always, reject_always}`
- 从 `tool_call` 通知收集 `locations` 到 `tool_locations[toolCallId]`
- 决策：`toolCall.locations` 或 `tool_locations[toolCallId]` 中任一 `path` 在已加载 buffer → 选 `kind=='allow_once'` 的 `optionId`；否则选 `reject_once`
- 响应 `{result:{outcome:{outcome:'selected', optionId}}}`；turn 已 cancel → `{result:{outcome:{outcome:'cancelled'}}}`

统一回写：`ch_sendraw(json_encode({jsonrpc:'2.0', id, result/error}) .. "\n")`。

## 8. 配置项、命令与映射

配置项（`plugin/acp.vim` 默认值）：

| 变量 | 默认 | 说明 |
|------|------|------|
| `g:acp_cmd` | `['opencode', 'acp']` | agent 启动命令 |
| `g:acp_cwd` | `''`（用 `getcwd()`） | 会话工作目录 |
| `g:acp_chat_bufname` | `'acp://chat'` | 对话 buffer 名 |
| `g:acp_map` | `1` | 是否设默认映射 |

命令：`:AcpOpen`（确保连接 + 打开 buffer）、`:AcpPrompt <text>`（`-nargs=+` 发送）、`:AcpCancel`（取消）、`:AcpClose`（关会话停 job）。

默认映射（`g:acp_map` 为真）：`<leader>ao` → `:AcpOpen`、`<leader>ap` → `:AcpPrompt `、`<leader>ac` → `:AcpCancel`。

## 9. 错误处理与退出清理

- `exit_cb`：清 `pending_calls`、置 `disconnected`、buffer 追加 `[已断开]`
- `json_decode` 用 `try/catch`，失败跳过并记日志
- 发送前检查 `job_status()`，已死提示重连
- `:AcpOpen` 检测 `disconnected` 时重连
- `VimLeave` autocmd 停 job
- stderr 默认忽略，设 `g:acp_logfile` 时写日志

## 10. 测试

- 协议验证脚本（`test_acp.vim` 风格）：`initialize` → `session/new` → `session/prompt` → 观察 `session/update` → 收 `stopReason`
- 端到端：`:AcpOpen` + `:AcpPrompt 说一句你好` 验证流式渲染；`:AcpCancel` 验证中断
- fs：读已打开 buffer（含未保存改动）；写文件验证 buffer 同步
- 权限：buffer 内 allow / buffer 外 reject
- 重连：kill agent → 断线提示 → `:AcpOpen` 重连
