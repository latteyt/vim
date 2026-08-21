vim9script

var channel: channel = null_channel
var job: job = null_job
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
