vim9script

import 'acp.vim' as acp

var opencode = acp.Agent.new()
var pending_permission: dict<any> = {}

def Fs_Read(id: number, params: dict<any>): void
  try
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
    opencode.Reply(id, { content: join(lines, "\n") })
  catch
    opencode.Error(id, -32000, v:exception)
  endtry
enddef

def Fs_Write(id: any, params: dict<any>): void
  try
    var path = get(params, 'path', '')
    var content = get(params, 'content', '')
    var lines = split(content, "\n", true)
    if lines == ['']
      lines = []
    endif
    var bnr = bufnr(path)
    if bnr != -1 && bufloaded(bnr)
      var saved_mod = getbufvar(bnr, '&modifiable', false)
      setbufvar(bnr, '&modifiable', true)
      var newlines: list<string> = empty(lines) ? [''] : lines
      var oldcnt = len(getbufline(bnr, 1, '$'))
      setbufline(bnr, 1, newlines)
      if oldcnt > len(newlines)
        deletebufline(bnr, len(newlines) + 1, '$')
      endif
      if !empty(path)
        writefile(getbufline(bnr, 1, '$'), path)
        setbufvar(bnr, '&modified', false)
      endif
      setbufvar(bnr, '&modifiable', saved_mod)
    else
      var dir = fnamemodify(path, ':h')
      if dir != '' && !isdirectory(dir)
        mkdir(dir, 'p')
      endif
      writefile(lines, path)
    endif
    opencode.Reply(id, v:null)
  catch
    opencode.Error(id, -32000, v:exception)
  endtry
enddef

def ReqPerm(id: any, params: dict<any>): void
  var toolCall = get(params, 'toolCall', {})
  var options = get(params, 'options', [])
  var content = get(toolCall, 'content', [])

  var diff = {}
  for c in content
    if get(c, 'type', '') == 'diff'
      diff = c
      break
    endif
  endfor

  if !empty(diff)
    pending_permission = {
      id: id,
      options: options,
      oldText: get(diff, 'oldText', ''),
      newText: get(diff, 'newText', ''),
      path: get(diff, 'path', ''),
      old_buf: -1,
      new_buf: -1,
    }
    Perm_ShowDiff()
    return
  endif

  # 无 diff 的权限（bash 等）：回退旧逻辑
  var locs = get(toolCall, 'locations', [])
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
  for o in options
    if get(o, 'kind', '') == want
      option_id = get(o, 'optionId', '')
      break
    endif
  endfor
  if option_id != ''
    opencode.Reply(id, { outcome: { outcome: 'selected', optionId: option_id } })
  else
    opencode.Reply(id, { outcome: { outcome: 'cancelled' } })
  endif
enddef

def Perm_WriteBuf(bnr: number, text: string): void
  if !bufloaded(bnr)
    bufload(bnr)
  endif
  setbufvar(bnr, '&buftype', 'nofile')
  setbufvar(bnr, '&buflisted', false)
  setbufvar(bnr, '&swapfile', false)
  setbufvar(bnr, '&modifiable', true)
  var lines = split(text, "\n", true)
  if empty(lines)
    lines = ['']
  endif
  var oldcnt = len(getbufline(bnr, 1, '$'))
  setbufline(bnr, 1, lines)
  if oldcnt > len(lines)
    deletebufline(bnr, len(lines) + 1, '$')
  endif
  setbufvar(bnr, '&modifiable', false)
enddef

def Perm_MapKeys(): void
  nnoremap <buffer> y <Cmd>call acp#Perm_Confirm('once')<CR>
  nnoremap <buffer> a <Cmd>call acp#Perm_Confirm('always')<CR>
  nnoremap <buffer> n <Cmd>call acp#Perm_Confirm('reject')<CR>
  nnoremap <buffer> q <Cmd>call acp#Perm_Confirm('reject')<CR>
  nnoremap <buffer> <Esc> <Cmd>call acp#Perm_Confirm('reject')<CR>
enddef

def Perm_ShowDiff(): void
  var oldText = get(pending_permission, 'oldText', '')
  var newText = get(pending_permission, 'newText', '')

  var old_buf = bufadd('')
  var new_buf = bufadd('')
  pending_permission['old_buf'] = old_buf
  pending_permission['new_buf'] = new_buf

  Perm_WriteBuf(old_buf, oldText)
  Perm_WriteBuf(new_buf, newText)

  try
    tabnew
    execute 'silent buffer ' .. old_buf
    diffthis
    Perm_MapKeys()
    rightbelow vsplit
    execute 'silent buffer ' .. new_buf
    diffthis
    Perm_MapKeys()
    echom '[acp] diff: y=allow_once  a=allow_always  n/q=reject'
  catch
  endtry
enddef

def Perm_Cleanup(): void
  if empty(pending_permission)
    return
  endif
  var old_buf = get(pending_permission, 'old_buf', -1)
  var new_buf = get(pending_permission, 'new_buf', -1)
  pending_permission = {}
  try
    tabclose
  catch
  endtry
  if old_buf != -1 && bufexists(old_buf)
    execute 'bwipeout! ' .. old_buf
  endif
  if new_buf != -1 && bufexists(new_buf)
    execute 'bwipeout! ' .. new_buf
  endif
enddef

def Perm_Finish(outcome: dict<any>): void
  if empty(pending_permission)
    return
  endif
  var id = get(pending_permission, 'id', '')
  opencode.Reply(id, { outcome: outcome })
  Perm_Cleanup()
enddef

# agent 发 $/cancel_request 取消 pending permission 时清理；返回 true 表示确有 pending 请求被取消，Agent 据此回 -32800
def OnCancelRequest(req_id: any): bool
  if !empty(pending_permission) && get(pending_permission, 'id', '') == req_id
    Perm_Cleanup()
    return true
  endif
  return false
enddef

export def Perm_Confirm(choice: string): void
  if empty(pending_permission)
    return
  endif
  var options = get(pending_permission, 'options', [])
  var want_kind = choice == 'reject' ? 'reject_once' : (choice == 'always' ? 'allow_always' : 'allow_once')
  var option_id = ''
  for o in options
    if get(o, 'kind', '') == want_kind
      option_id = get(o, 'optionId', '')
      break
    endif
  endfor
  if option_id != ''
    Perm_Finish({ outcome: 'selected', optionId: option_id })
  else
    Perm_Finish({ outcome: 'cancelled' })
  endif
enddef

# 取消 prompt turn 时，响应 pending permission 为 cancelled（schema: RequestPermissionOutcome::Cancelled）
def Perm_Abort(): void
  Perm_Finish({ outcome: 'cancelled' })
enddef

export def Perm_Pending(): dict<any>
  return pending_permission
enddef

def Agent_Start(): bool
  var cwd = exists('g:acp_cwd') && g:acp_cwd != '' ? g:acp_cwd : getcwd()
  var cmd = exists('g:acp_cmd') ? g:acp_cmd : ['opencode', 'acp']
  return opencode.Start(cwd, cmd)
enddef

export def Session_Open(): bool
  return Agent_Start()
enddef

def Update(sid: string, update: dict<any>): void
  var kind = get(update, 'sessionUpdate', '')
  if kind == 'agent_message_chunk'
    Ui_AppendMsgChunk(sid, update, '')
  elseif kind == 'user_message_chunk'
    Ui_AppendMsgChunk(sid, update, '> ')
  elseif kind == 'tool_call'
    Ui_AppendLine(sid, '[工具] ' .. get(update, 'title', ''))
  elseif kind == 'tool_call_update'
    Ui_AppendLine(sid, '[工具] ' .. get(update, 'title', '') .. ' -> ' .. get(update, 'status', ''))
  elseif kind == 'plan'
    for e in get(update, 'entries', [])
      Ui_AppendLine(sid, get(e, 'priority', '') .. ': ' .. get(e, 'content', ''))
    endfor
  endif
enddef

def Ui_Buf(sid: string): number
  var bname = 'acp://chat/' .. sid
  var bnr = bufnr(bname, true)
  if !bufloaded(bnr)
    bufload(bnr)
  endif
  setbufvar(bnr, '&buftype', 'nofile')
  setbufvar(bnr, '&buflisted', false)
  setbufvar(bnr, '&swapfile', false)
  setbufvar(bnr, '&undofile', false)
  setbufvar(bnr, '&modifiable', false)
  setbufvar(bnr, 'acp_chat', 1)
  return bnr
enddef

def Ui_AppendLine(sid: string, text: string): void
  var bnr = Ui_Buf(sid)
  setbufvar(bnr, '&modifiable', true)
  appendbufline(bnr, '$', text)
  setbufvar(bnr, '&modifiable', false)
  Ui_Scroll(bnr)
enddef

def Ui_AppendMsgChunk(sid: string, update: dict<any>, prefix: string): void
  var content = get(update, 'content', {})
  if get(content, 'type', '') != 'text'
    return
  endif
  var text = get(content, 'text', '')
  var msg_id = get(update, 'messageId', '')
  if !has_key(opencode.loaded_sessions, sid)
    return
  endif
  var s = opencode.loaded_sessions[sid]
  if msg_id != '' && msg_id != s.cur_msg_id
    Ui_AppendLine(sid, prefix .. text)
    s.cur_msg_id = msg_id
  else
    Ui_AppendChunk(sid, text)
  endif
enddef

def Ui_AppendChunk(sid: string, text: string): void
  var bnr = Ui_Buf(sid)
  var lastline = getbufoneline(bnr, '$', '$')
  setbufvar(bnr, '&modifiable', true)
  if empty(lastline)
    appendbufline(bnr, '$', text)
  else
    setbufline(bnr, '$', lastline[0] .. text)
  endif
  setbufvar(bnr, '&modifiable', false)
  Ui_Scroll(bnr)
enddef

def Ui_EchoUser(sid: string, text: string): void
  Ui_AppendLine(sid, '> ' .. text)
enddef

def Ui_Scroll(bnr: number): void
  var wins = win_findbuf(bnr)
  for w in wins
    win_execute(w, 'normal! G')
  endfor
enddef

def Ui_ShowCurrent(): void
  var sid = opencode.current_sid
  if sid == ''
    return
  endif
  var bnr = Ui_Buf(sid)
  if win_findbuf(bnr)->empty()
    try
      execute 'sbuffer ' .. bnr
    catch
    endtry
  endif
enddef

def OnSessionCreated(sid: string): void
  var bnr = Ui_Buf(sid)
  if has_key(opencode.loaded_sessions, sid)
    opencode.loaded_sessions[sid].bufnr = bnr
  endif
  Ui_ShowCurrent()
enddef

def OnSessionRemoved(sid: string): void
  Ui_ShowCurrent()
enddef

def OnSessionList(sess: list<dict<any>>): void
  Ui_ListPopup(sess)
enddef

def Ui_ListPopup(sess: list<dict<any>>): void
  if empty(sess)
    echom '[acp] no sessions'
    return
  endif
  var lines: list<string> = []
  var idx = 1
  for s in sess
    var sid = get(s, 'sessionId', '')
    var title = get(s, 'title', '')
    var mark = sid == opencode.current_sid ? '*' : ' '
    lines->add(printf('%2d [%s] %s  %s', idx, mark, sid, title))
    idx += 1
  endfor
  popup_create(lines, { line: 1, col: 1 })
enddef

export def Ui_Open(): void
  if Agent_Start()
    Ui_ShowCurrent()
  endif
enddef

export def Session_Prompt(text: string): void
  if opencode.Prompt(text)
    Ui_EchoUser(opencode.current_sid, text)
  endif
enddef

export def Session_Cancel(): void
  opencode.Cancel()
  Perm_Abort()
enddef

export def Session_New(): void
  opencode.NewSession()
enddef

export def Session_List(): void
  if !opencode.HasCap('list')
    echom '[acp] agent does not support session/list'
    return
  endif
  opencode.ListSessions()
enddef

export def Session_Switch(arg: string): void
  var sid = arg
  if arg =~ '^\d\+$'
    sid = opencode.Session_ByIdx(str2nr(arg))
  endif
  if !opencode.SwitchTo(sid)
    echom '[acp] no such session: ' .. sid
    return
  endif
  Ui_ShowCurrent()
enddef

export def Session_Load(arg: string): void
  if !opencode.HasCap('load')
    echom '[acp] agent does not support session/load'
    return
  endif
  var sid = arg
  if arg =~ '^\d\+$'
    sid = opencode.Session_ByIdx(str2nr(arg))
  endif
  opencode.LoadSession(sid)
enddef

export def Session_CloseSession(arg: string): void
  if !opencode.HasCap('close')
    echom '[acp] agent does not support session/close'
    return
  endif
  var sid = arg
  if arg =~ '^\d\+$'
    sid = opencode.Session_ByIdx(str2nr(arg))
  endif
  if sid == ''
    sid = opencode.current_sid
  endif
  if sid == ''
    return
  endif
  opencode.CloseSession(sid)
enddef

export def Ready(): bool
  return opencode.Ready()
enddef

export def CurrentBuf(): number
  var sid = opencode.current_sid
  if sid == ''
    return -1
  endif
  return Ui_Buf(sid)
enddef

export def CurrentSession(): string
  return opencode.current_sid
enddef

export def SessionCount(): number
  return len(opencode.loaded_sessions)
enddef

export def Close(): void
  opencode.Close()
enddef
