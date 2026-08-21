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
    if decoded.method == 'fs/read_text_file'
      Fs_Read(decoded.id, decoded.params)
    elseif decoded.method == 'fs/write_text_file'
      Fs_Write(decoded.id, decoded.params)
    elseif decoded.method == 'session/request_permission'
      Perm_Decide(decoded.id, decoded.params)   # Task 6
    endif
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

def Ui_Buf(): number
  var bname = exists('g:acp_chat_bufname') ? g:acp_chat_bufname : 'acp://chat'
  var bnr = bufnr(bname, true)
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
  setbufvar(bnr, '&modifiable', true)
  appendbufline(bnr, '$', text)
  setbufvar(bnr, '&modifiable', false)
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
