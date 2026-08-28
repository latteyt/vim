vim9script

import 'client.vim' as client

# sid -> cur_msg_id
var loaded_sessions: dict<any> = {}


export def List(c: dict<any>, cwd: string = null_string)
  # session/list is Idempotency
  if !c.Capabilities->get('sessionCapabilities', {})->has_key('list')
    echoerr "[ACP] DO NOT support session/list"
    return
  endif

  client.Request(c, 'session/list', { cwd: cwd ?? c.cwd },
    (resp: dict<any>) => {
      if empty(resp) || resp->has_key('error')
        echoerr '[ACP] list sessions failed'
        return
      endif
      var sessions: list<dict<any>> = resp->get('result', {})->get('sessions', [])
      if empty(sessions)
        echom '[ACP] no sessions'
        return
      endif
      var lines: list<string> = sessions->copy()->map((idx, s) => {
        var sid = get(s, 'sessionId', '')
        var title = get(s, 'title', '')
        var mark = sid == c.cur_sid ? '*' : ' '
        return printf('%2d [%s] %s  %s', idx, mark, sid, title)
      })
      popup_create(lines, { line: 1, col: 1 })
    })
enddef

def SessionNew(c: dict<any>, cwd: string = null_string)
  if c.state != 'IDLE'
    echoerr "[ACP] Client is NOT ready"
    return
  endif

  c.state = 'BUSY'

  client.Request(c, 'session/new', { cwd: cwd ?? c.cwd, mcpServers: [] },
    (resp: dict<any>) => {
      if empty(resp) || resp->has_key('error')
        echoerr '[ACP] new session failed'
        return
      endif
      var sid = resp->get('result', {})->get('sessionId', '')
      c.cur_sid = sid
      var bnr: number = ui#ChatBuf(sid)
      if !loaded_sessions->has_key(sid)
        loaded_sessions[sid] = -1
      endif

      c.state = 'IDLE'
    })
enddef

def Load(c: dict<any>, sid: string, cwd: string = null_string)
  if c.state != 'IDLE'
    echoerr "[ACP] Client is NOT ready"
    return
  endif

  if !c.Capabilities->get('loadSession', false)
    echoerr "[ACP] DO NOT support session/load"
    return
  endif

  c.state = 'BUSY'
  client.Request(c, 'session/load', { sessionId: sid, cwd: cwd ?? c.cwd, mcpServers: [] },
    (resp: dict<any>) => {
      if empty(resp) || resp->has_key('error')
        echoerr '[ACP] load session failed'
        return
      endif
      c.cur_sid = sid
      var bnr: number = ui#ChatBuf(sid)
      if !loaded_sessions->has_key(sid)
        loaded_sessions[sid] = -1
      endif
      c.state = 'IDLE'
    })
enddef

def Prompt(c: dict<any>, text: string)
  if c.state != 'IDLE'
    echoerr "[ACP] Client is NOT ready"
    return
  endif

  c.state = 'BUSY'
  client.Request(c, 'session/prompt', {
    sessionId: c.cur_sid,
    prompt: [{ type: 'text', text: text }],
  }, (resp: dict<any>) => {
    if resp->has_key('error')
      echoerr '[ACP] prompt session failed'
      return
    endif
  })

  var bnr: number = ui#ChatBuf(c.cur_sid)
  ui#AppendLine(bnr, '> ' .. text)
enddef


export def ReqPerm(c: dict<any>, id: number, params: dict<any>)
  client.Log('NEW', json_encode(params))
enddef

export def Update(c: dict<any>, sid: string, change: dict<any>)
  var kind = get(change, 'sessionUpdate', '')
  var bnr = ui#ChatBuf(sid)
  if kind == 'agent_message_chunk' || kind == 'user_message_chunk'
    var msg_id: string = change->get('messageId', '')
    var text: string = change->get('content', {})->get('text', '')
    var cur_msg_id = loaded_sessions->get(sid, -1)
    if msg_id != cur_msg_id
      loaded_sessions[sid] = msg_id
      ui#AppendLine(bnr, kind .. ' > ' .. text)
      c.state = 'IDLE' # unlock
    else
      ui#AppendChunk(bnr, text)
    endif
  elseif kind == 'tool_call'
    ui#AppendLine(bnr, '[TOOL] ' .. get(change, 'title', ''))
    c.state = 'IDLE' # unlock
  elseif kind == 'tool_call_update'
    ui#AppendLine(bnr, '[TOOL] ' .. get(change, 'title', '') .. ' -> ' .. get(change, 'status', ''))
    c.state = 'IDLE' # unlock
  elseif kind == 'plan'
    for e in get(change, 'entries', [])
      ui#AppendLine(bnr, get(e, 'priority', '') .. ': ' .. get(e, 'content', ''))
    endfor
    c.state = 'IDLE' # unlock
  endif
enddef
