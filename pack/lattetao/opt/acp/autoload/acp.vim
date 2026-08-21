vim9script

var channel: channel = null_channel
var job: job = null_job
var pending_calls: dict<func> = {}
var next_id: number = 1
var state: string = 'disconnected'
var session_id: string = ''
var agent_caps: dict<any> = {}

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
    if has_key(pending_calls, decoded.id)
      var cb = remove(pending_calls, decoded.id)
      cb(decoded)
    endif
  elseif has_key(decoded, 'method')
    OnNotification(decoded)
  endif
enddef

def OnStderr(ch: channel, msg: string)
  if exists('g:acp_logfile')
    writefile([msg], g:acp_logfile, 'a')
  endif
enddef

def OnExit(ch: channel, status: number)
  pending_calls = {}
  state = 'disconnected'
  session_id = ''
enddef

export def Rpc_Send(method: string, params: dict<any>, Callback: func = v:null): void
  var req = { jsonrpc: '2.0', id: next_id, method: method, params: params }
  next_id += 1
  if Callback != v:null
    pending_calls[req.id] = Callback
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

def Init_(): void
  Rpc_Send('initialize', {
    protocolVersion: 1,
    clientCapabilities: { fs: { readTextFile: true, writeTextFile: true } },
    clientInfo: { name: 'acp-vim', title: 'ACP Vim', version: '0.1.0' },
  }, (resp) => OnInitResp(resp))
enddef

def OnInitResp(resp: dict<any>): void
  if has_key(resp, 'error') || get(get(resp, 'result', {}), 'protocolVersion', 0) != 1
    state = 'disconnected'
    return
  endif
  agent_caps = get(get(resp, 'result', {}), 'agentCapabilities', {})
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
  session_id = get(get(resp, 'result', {}), 'sessionId', '')
  state = 'ready'
enddef

export def Session_Prompt(text: string): void
  if state != 'ready'
    return
  endif
  Ui_EchoUser(text)
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

def OnNotification(msg: dict<any>): void
  if msg.method == 'session/update'
    OnUpdate(get(msg.params, 'update', {}))
  endif
enddef

def OnUpdate(update: dict<any>): void
  var kind = get(update, 'sessionUpdate', '')
  if kind == 'agent_message_chunk'
    Ui_AppendAgent(update)
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

def Ui_AppendLine(text: string): void
  # Task 4 完善
enddef

def Ui_AppendAgent(update: dict<any>): void
  # Task 4 完善
enddef

def Ui_EchoUser(text: string): void
  # Task 4 完善
enddef
