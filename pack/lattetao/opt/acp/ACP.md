# ACP（Agent Client Protocol）总结

## 1. 是什么

ACP 是标准化 **AI 编码代理（Agent）与代码编辑器/IDE（Client）之间通信** 的开放协议，由 Zed Industries 发起。定位类似 LSP 标准化了编辑器与语言服务器的关系，ACP 标准化了编辑器与 AI 代理的关系，解决 "N×M" 集成问题（每个编辑器不必为每个代理写专属集成）。

## 2. 底层通信模型

- 基于 **JSON-RPC 2.0**，两种消息：
  - **Methods（方法）**：请求-响应，返回 `result` 或 `error`
  - **Notifications（通知）**：单向消息，无响应（用于流式实时更新）
- 复用 MCP 的类型表示（如 `ContentBlock`），但新增面向编码 UX 的自定义类型（如 diff）
- 默认用户可读文本格式为 **Markdown**
- 本地场景通过 **stdio（stdin/stdout）** 通信；远程场景走 HTTP/WebSocket（仍在完善）
- 一个连接可支持**多个并发会话**（session）

## 3. 角色

关键特点是**双向请求**：不只 Client 调用 Agent，Agent 也能反过来调用 Client。

| 角色 | 典型例子 | 职责 |
|------|---------|------|
| **Client** | Zed、JetBrains、Neovim、CLI/Web UI | 管理环境、用户交互、控制资源访问、渲染输出 |
| **Agent** | claude-agent-acp、codex-acp、opencode、gemini | 用 AI 自主改代码，通常是 Client 的子进程 |

Client 通常是编辑器，但不限于编辑器。角色由**谁实现哪些方法**决定，而非名字。

### 方法注册表（ACP v1）

`agentMethods`（Agent 实现，供 Client 调用）：

| 方法 | 作用 |
|------|------|
| `authenticate` | 对代理进行身份认证（若需要） |
| `initialize` | 握手：协商协议版本、交换能力 |
| `session/cancel` | 取消正在进行的操作（通知，无响应） |
| `session/load` | 加载/恢复历史会话（需 `loadSession` 能力） |
| `session/new` | 创建新会话 |
| `session/prompt` | 发送用户提示，触发核心对话流程 |
| `session/set_config_option` | 设置会话级配置选项 |
| `session/set_mode` | 切换代理运行模式 |

`clientMethods`（Client 实现，供 Agent 调用）：

| 方法 | 作用 |
|------|------|
| `fs/read_text_file` / `fs/write_text_file` | 读写文件（需 `fs` 能力） |
| `session/request_permission` | 工具调用前请求用户授权 |
| `session/update` | Agent 向 UI 实时推送会话更新（通知） |
| `terminal/create` / `kill` / `output` / `release` / `wait_for_exit` | 终端全生命周期管理 |

### 典型消息流程

```
1. 初始化阶段
   Client → Agent : initialize    （协商版本与能力）
   Client → Agent : authenticate  （如需认证）

2. 会话建立（二选一）
   Client → Agent : session/new   （新建）
   Client → Agent : session/load  （恢复历史）

3. 提示轮次（Prompt Turn）
   Client → Agent : session/prompt
   Agent → Client : session/update        （流式推送消息块/工具调用/计划）
   Agent → Client : fs/read_text_file 等  （读写文件）
   Agent → Client : session/request_permission（请求授权）
   Client → Agent : session/cancel        （用户打断）
   轮次结束 → Agent 返回 session/prompt 响应（带 stop reason）
```

## 4. 文件路径 vs URI

不是所有路径都是 URI，分两处约定：

1. **文件系统方法**（`fs/read_text_file`、`fs/write_text_file`）的 `path` 是**绝对路径字符串**（如 `/home/user/project/src/main.py`），不是 URI。
2. **内容块（content blocks）** 里的资源引用才是 **URI**（`resource_link`、`embedded resource`，如 `file:///home/user/document.pdf`）。

即：方法调用用绝对路径字符串；资源引用用 URI。两者不要混用。

## 5. capability（能力）概念

有，且几乎与 LSP 一致。`initialize` 握手时**双向交换能力**：

- **`clientCapabilities`**（Client → Agent）：`fs.readTextFile` / `fs.writeTextFile`、`terminal`、`session.configOptions`、`promptCapabilities`（`image`/`audio`/`embeddedContext`）
- **`agentCapabilities`**（Agent → Client）：`loadSession`、`sessionCapabilities`（`list`/`close`/`fork`/`resume`）、`promptCapabilities`、`auth.logout`、`mcpCapabilities`

协议强制：能力缺失时**禁止**调用对应方法（`MUST` 检查）。例如 agentic.nvim 的 `load_session` 先检查 `agent_capabilities.loadSession`，`list_sessions` 先检查 `sessionCapabilities.list`。

## 6. UTF-16 位置编码

**不需要**，这是 ACP 与 LSP 的关键差异。

- LSP 用 `Position{line, character}`，`character` 是 UTF-16 code unit，编辑器要做 UTF-8→UTF-16 转换。
- ACP v1 **没有字符级位置概念**，只用两种定位：
  1. **行号（1-based）**，仅行号、无列偏移：`fs/read_text_file` 的 `line` + `limit`、工具调用 `locations` 的 `path` + `line`
  2. **整段文本字符串**：diff 用 `oldText`/`newText` 全文，不涉及行/列计算

官方约定："Line numbers are 1-based"。因此写 client 只需关心行号（1 开始）和字符串内容。

## 7. 同步 vs 异步

底层传输（stdio）全是**非阻塞异步**的（libuv 事件循环），没有真正的同步调用。区分在 JSON-RPC 消息语义：

- **请求-响应**（带 `id` + callback）：`initialize`、`authenticate`、`session/new`、`session/load`、`session/list`、`session/prompt`、`session/set_mode`、`session/set_config_option`
- **通知**（无 `id`，fire-and-forget）：`session/cancel`
- **入站通知**（Agent → Client）：`session/update`、`session/request_permission`、`fs/*`（agentic.nvim 直接忽略 fs）

实现上：请求方用 `callbacks[id]` 注册回调，响应到达时按 `id` 匹配。

## 8. 版本现状

- **ACP v1** 已稳定，是当前主流实现。
- **ACP v2** 处于 draft 阶段：`session/load` → `session/resume`、新 prompt 生命周期（`session/state_update`）、`session/fork`/`session/close` 等。
- **opencode**（截至 1.18.19）只支持 ACP v1：`initialize` 响应硬编码返回 `protocolVersion: 1`（源码 `packages/opencode/src/acp/service.ts`）。
- **agentic.nvim**（Neovim ACP client）也只实现 v1：`protocol_version = 1`（`lua/agentic/acp/acp_client.lua:61`），无任何 v2 特性。

## 9. 与 Vim9script 的契合点

因为 ACP 规避了 UTF-16 转换，且行号 1-based，Vim 天然契合：

1. 行号 1-based 零转换：`line('.')`、`getline(n)` 本身 1-based，与 ACP 完全一致。
2. diff 用全文 `oldText`/`newText`：`getline()` 取整块文本直接拼接。
3. stdio JSON-RPC 现成：`job_start()` / `ch_open()` + channel，配 `json_encode()`/`json_decode()`。

## 10. 关键约定与扩展性

- 所有文件路径必须为**绝对路径**；行号从 1 开始。
- 属性命名 `camelCase`，判别字段用 `snake_case`。
- 三个扩展机制：`_meta` 字段加自定义数据、`_` 前缀定义自定义方法、`initialize` 声明自定义能力。
- 官方 SDK：Rust、TypeScript 达 1.0，另有 Kotlin、Java、Python 及社区库。
