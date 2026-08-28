vim9script

export def Log(tag: string, data: string)
  var line = strftime('%Y-%m-%d %H:%M:%S') .. ' [' .. tag .. '] ' .. data
  writefile([line], '/tmp/acp.log', 'a')
enddef

# ACP Client：连接 + 会话集合的生命周期管理。
# Client 用 dict 承载状态，方法通过首参数注入 client。

export def New(cmd: list<string>): dict<any>
  var c: dict<any> = {
    bufname: '',
    state: 'DEAD',   # DEAD/IDLE/BUSY
    Capabilities: {},
    cmd: cmd,
    _job: null_job,
    _channel: null_channel,
    _next_id: 1,
    _pending_calls: {},
  }
  return c
enddef


# ---- 连接生命周期 ----

export def Start(c: dict<any>, cwd: string): bool
  var opts: dict<any> = {
    in_mode: 'nl', out_mode: 'nl', err_mode: 'nl',
    out_cb: (ch: channel, msg: string) => {
      Log('RECV', msg)
      Dispatch(c, msg)
    },
    err_cb: (ch: channel, msg: string) => Log('ERR', msg),
    exit_cb: (ch: channel, status: number) => {
      Log('EXIT', string(status))
      Reset(c)
    },
  }
  c._job = job_start(c.cmd + ['--cwd', cwd], opts)
  c._channel = job_getchannel(c._job)

  if job_status(c._job) != 'run' || ch_status(c._channel) != 'open'
    return false
  endif

  c.bufname = 'acp://chat/' .. join(c.cmd + ['--cwd', cwd])
  if bufnr(c.bufname) != -1
    execute 'bwipeout! ' .. bufnr(c.bufname)
  endif
  var bnr: number = bufnr(c.bufname, true)
  if !bufloaded(bnr) | bufload(bnr) | endif

  setbufvar(bnr, '&buftype', 'prompt')
  setbufvar(bnr, '&buflisted', false)
  setbufvar(bnr, '&swapfile', false)
  setbufvar(bnr, '&undofile', false)
  setbufvar(bnr, '&modifiable', false)
  setbufvar(bnr, '&filetype', 'acpchat')
  setbufvar(bnr, 'cwd', cwd)


  if win_findbuf(bnr)->empty()
    execute('sbuffer ' .. bnr)
  else
    execute('buffer ' .. bnr)
  endif

  Log('START', string(c.cmd) .. ' cwd=' .. cwd)
  return true
enddef

export def Reset(c: dict<any>)
  Log('RESET', 'close channel and stop job')
  if ch_status(c._channel) == 'open' | ch_close(c._channel) | endif
  if job_status(c._job) == 'run' | job_stop(c._job) | endif
  c._job = null_job
  c._channel = null_channel
  c._next_id = 1
  c._pending_calls = {}
  c.Capabilities = {}
  c.bufname = ''
  c.state = 'DEAD'
enddef


# ---- channel 回调 ----
def Dispatch(c: dict<any>, msg: string)
  var decoded: dict<any> = json_decode(msg) # Fail Fast
  if has_key(decoded, 'method') && has_key(decoded, 'id')
    var params = get(decoded, 'params', {})
    if decoded.method == 'fs/read_text_file'
      fs#ReadTextFile(c, decoded.id, params)
    elseif decoded.method == 'fs/write_text_file'
      fs#WriteTextFile(c, decoded.id, params)
    elseif decoded.method == 'session/request_permission'
      session#ReqPerm(c, decoded.id, params)
    else
      echoerr '[ACP] MSG : ' .. msg
    endif
  elseif has_key(decoded, 'id')
    if has_key(c._pending_calls, decoded.id)
      var Cb: func = remove(c._pending_calls, decoded.id)
      Cb(decoded)
    else
      echoerr '[ACP] MSG : ' .. msg
    endif
  elseif has_key(decoded, 'method')
    if decoded.method == 'session/update'
      ui#ChatBufUpdate(c.bufname->bufnr(), decoded->get('params'))
    else
      echoerr '[ACP] MSG : ' .. msg
    endif
  endif
enddef


# ---- RPC 发送 ----
# Callback 非空：异步发送，响应按 id 匹配回调。
# Callback 为空：同步发送并阻塞读一行响应。
export def Request(c: dict<any>, method: string, params: dict<any>, Callback: func = null_function): any
  var req = { jsonrpc: '2.0', id: c._next_id, method: method, params: params }
  c._next_id += 1
  var raw = json_encode(req)
  Log('SEND', raw)
  if Callback == null_function
    var resp = ch_evalraw(c._channel, raw .. "\n", { timeout: 30000 })
    Log('RECV', resp)
    return json_decode(resp)
  else
    c._pending_calls[req.id] = Callback
    ch_sendraw(c._channel, raw .. "\n")
    return {}
  endif
enddef

export def Reply(c: dict<any>, id: any, result: any)
  var raw = json_encode({ jsonrpc: '2.0', id: id, result: result })
  Log('SEND', raw)
  ch_sendraw(c._channel, raw .. "\n")
enddef

export def Error(c: dict<any>, id: any, code: number, message: string)
  var raw = json_encode({ jsonrpc: '2.0', id: id, error: { code: code, message: message } })
  Log('SEND', raw)
  ch_sendraw(c._channel, raw .. "\n")
enddef

export def Notify(c: dict<any>, method: string, params: dict<any>)
  var raw = json_encode({ jsonrpc: '2.0', method: method, params: params })
  Log('SEND', raw)
  ch_sendraw(c._channel, raw .. "\n")
enddef


# ---- 命名步骤状态机 ----
# flow 是 dict<step_name, {method, params, on?, next?}>
# params 可为 dict 或 func(c)->dict（依赖前序结果时用 func）。
# 每步完成：有 on → on(c, resp) 返回下个 step 名（'' 结束）；
#           否则用 next；都没有则结束。失败时自动 echoerr 并停止。
def Next(c: dict<any>, flow: dict<any>, cur: string)
  if !has_key(flow, cur)
    return
  endif
  var step = flow[cur]
  var method: string = get(step, 'method', '')
  var params: dict<any> = {}
  if has_key(step, 'params')
    if type(step.params) == v:t_func
      var Fn: func = step.params
      params = Fn(c)
    else
      params = step.params
    endif
  endif
  Request(c, method, params, (resp: dict<any>) => {
    if empty(resp) || resp->has_key('error')
      echoerr '[ACP] ' .. method .. ' failed'
      return
    endif
    var next: string = ''
    if has_key(step, 'on')
      var Cb: func = step.on
      next = Cb(c, resp)
    elseif has_key(step, 'next')
      next = step.next
    endif
    Next(c, flow, next)
  })
enddef

export def Execute(c: dict<any>, flow: dict<any>, start: string)
  Next(c, flow, start)
enddef

