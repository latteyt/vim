vim9script


export def AppendLine(bnr: number, text: string)
  setbufvar(bnr, '&modifiable', true)
  appendbufline(bnr, '$', split(text, "\n", true))
  setbufvar(bnr, '&modifiable', false)
  setbufvar(bnr, '&modified', false)
  win_findbuf(bnr)->copy()
    ->foreach((i, w) => win_execute(w, 'normal! G'))
enddef


export def AppendChunk(bnr: number, text: string)
  var parts: list<string> = split(text, "\n", true)
  if empty(parts)
    return
  endif
  setbufvar(bnr, '&modifiable', true)
  var lastline: string = getbufoneline(bnr, '$')
  setbufline(bnr, '$', lastline .. parts[0])
  if len(parts) > 1
    appendbufline(bnr, '$', parts[1 :])
  endif
  setbufvar(bnr, '&modifiable', false)
  setbufvar(bnr, '&modified', false)

  win_findbuf(bnr)->copy()
    ->foreach((i, w) => win_execute(w, 'normal! G'))
enddef


def AppendMsgChunk(bnr: number, update: dict<any>, prefix: string): void
  if update->get('content')->get('type') != 'text'
    return
  endif

  var text: string = update->get('content')->get('text')
  var update_msg_id: string = update->get('messageId')
  var buf_msg_id: string = bnr->getbufvar('messageId', '')
  if update_msg_id != buf_msg_id
    AppendLine(bnr, "\n")
    AppendLine(bnr, prefix)
    AppendLine(bnr, text)
    bnr->setbufvar('messageId', update_msg_id)
  else
    AppendChunk(bnr, text)
  endif
enddef



export def ChatBufUpdate(bnr: number, params: dict<any>)
  if bnr == -1 | return | endif
  if empty(params) | return | endif
  if getbufvar(bnr, 'sessionId') != get(params, 'sessionId')
    return
  endif
  var update: dict<any> = params->get('update')
  var kind = update->get('sessionUpdate')
  if kind == 'agent_message_chunk'
    AppendMsgChunk(bnr, update, "Agent  ")
  elseif kind == 'user_message_chunk'
    AppendMsgChunk(bnr, update, "User   ")
  elseif kind == 'tool_call'
    var text: string = $'[{get(update, 'kind')}]  {get(update, 'title')} ->  {get(update, 'status')}'
    var lnum = getbufinfo(bnr)[0].linecount
    AppendLine(bnr, text)
    # prop_add(lnum, 1, {bufnr: bnr, type: 'acpTool', length: len(text) - 1})
  elseif kind == 'tool_call_update'
    var text: string = $'[{get(update, 'kind')}]  {get(update, 'title')} ->  {get(update, 'status')}'
    var lnum = getbufinfo(bnr)[0].linecount
    AppendLine(bnr, text)
  elseif kind == 'plan'
    for e in get(update, 'entries', [])
      AppendLine(bnr, get(e, 'priority', '') .. ': ' .. get(e, 'content', ''))
    endfor
  endif
enddef
