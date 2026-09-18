vim9script

import autoload 'lsp/util.vim' as util

var timer: number = -1
var pendings: list<number> = []
var req_ctx: dict<any> = {
  bufnr: -1,
  lnum: -1,
  triggerKind:  1
}

const KindChars: list<string> = [
  '',  't', 'm', 'f', 'C', 'F',
  'v', 'c', 'i', 'M', 'p',
  'u', 'V', 'e', 'k', 'S',
  'C', 'f', 'r', 'F', 'E',
  'd', 's', 'E', 'o', 'T',
  'B',
]

export def OnKeyInput(bufnr: number): void
  if mode() !~# '^i' | return | endif # not for cmdline

  if !getbufvar(bufnr, 'lsp_did_open', false) | return | endif
  var server: dict<any> = getbufvar(bufnr, 'lsp_server', {})
  if server->get('state', 'stopped') != 'ready' | return | endif
  var keys: list<string> = [ "\<BS>", "\<C-h>", "\<Del>", "\<C-w>", "\<C-u>" ]
  if index(keys, v:char) == -1
    return
  endif
  timer_stop(timer)
  timer = timer_start(250, (_: number) => OnTimer())
enddef

export def OnInsertChar(bufnr: number): void
  if !getbufvar(bufnr, 'lsp_did_open', false) | return | endif
  var server: dict<any> = getbufvar(bufnr, 'lsp_server', {})
  if server->get('state', 'stopped') != 'ready' | return | endif
  timer_stop(timer)
  timer = timer_start(250, (_: number) => OnTimer())
enddef


def OnTimer(): void
  var bufnr: number = bufnr('%')
  if !getbufvar(bufnr, 'lsp_did_open', false) | return | endif
  var server: dict<any> = getbufvar(bufnr, 'lsp_server', {})
  if server->get('state', 'stopped') != 'ready' | return | endif
  listener_flush(bufnr)
  pendings->foreach((_, id) => ch_sendexpr(server.channel, {method: '$/cancelRequest', params: {id: id}}))
  pendings = []

  if pumvisible() | return | endif

  var lnum: number = line('.')
  var col: number = col('.')
  var cline: string = getline('.')
  var prev: string = col > 1 ?
    cline->strpart(col - 2, 1) : ''
  var triggers = server.capabilities->get('completionProvider', {})
    ->get('triggerCharacters', [])

  if prev !~# '\k' && index(triggers, prev) == -1
    return
  endif

  # NOTE: we do not care for the TriggerForIncompleteCompletions (3)
  # just take it as Invoked (1) for simplification
  var context: dict<any> = index(triggers, prev) == -1 ? { triggerKind: 1 }
    : { triggerKind: 2, triggerCharacter: prev }

  var filepath: string = getbufinfo(bufnr)[0]->get('name', '')
  if filepath->empty() | return | endif

  var params: dict<any> = {
    textDocument: {uri: util.PathToUri(filepath)},
    position: {line: lnum - 1, character: cline->utf16idx(col - 1, true)},
    context: context,
  }
  util.Log('completion request: ' .. json_encode(params))
  req_ctx.bufnr = bufnr
  req_ctx.lnum = lnum
  req_ctx.triggerKind = context.triggerKind
  var r: dict<any> = ch_sendexpr(server.channel, {
    method: 'textDocument/completion',
    params: params,
  }, {callback: (ch: channel, resp: dict<any>) => OnComplete(resp)})
  pendings->add(r['id'])
enddef




def Normalize(startidx: number, cline: string, item: dict<any>): dict<any>
  var word: string = ''
  if item->has_key('textEdit')
    var idx: number  = cline->byteidxcomp(item.textEdit.range.start.character, true)
    if startidx < idx
      util.Log('prefix padding: ' .. json_encode(item))
    endif
    word = strpart(cline, startidx, idx - startidx) .. item.textEdit.newText
  else
    word = item.label
  endif

  var doc: any = get(item, 'documentation', '')
  var info: string = type(doc) == v:t_string ? doc :
    type(doc) == v:t_dict ? get(doc, 'value', '') : ''

  return {
    word: word,
    abbr: item.label,
    kind: KindChars[item.kind],
    menu: get(item, 'detail', ''),
    info: info,
    user_data: { textEdits: get(item, 'additionalTextEdits', []) },
  }
enddef


def OnComplete(resp: dict<any>): void
  util.Log('completion response: ' .. json_encode(resp))
  var idx: number = pendings->index(resp.id)
  if idx != -1 | pendings->remove(idx) | endif

  if has_key(resp, 'error') || !has_key(resp, 'result')
    return
  endif

  if req_ctx.bufnr != bufnr('%') || req_ctx.lnum != line('.')
    return
  endif

  var items: list<dict<any>> = get(resp.result, 'items', [])

  # HERE get the start byte idx before cursor use \k
  var cline = getline('.')
  var prefix: string = cline->strpart(0, col('.') - 1)
  var base: string = prefix->matchstr('\k\+$')

  var startidx: number = prefix->len() - base->len()
  var startidxs: list<number> = items->copy()->map((_, item) => {
    return item->has_key('textEdit') ?
      cline->byteidxcomp(item.textEdit.range.start.character, true)
      : startidx
  })
  startidx = min(startidxs)
  base = prefix->strpart(startidx)
  util.Log($'base : {base}, startidx : {startidx}')

  items->map((_, item) => Normalize(startidx, cline, item))

  if req_ctx.triggerKind != 2
    items = matchfuzzy(items, base, { matchseq: 1, key: 'word' })
    items->sort((a, b) =>
      (stridx(a.word, base) == 0 ? 0 : 1) - (stridx(b.word, base) == 0 ? 0 : 1))
  endif

  if mode() =~# '^i'
    complete(startidx + 1, items)
  endif
enddef


export def OnDone(bufnr: number): void
  if !getbufvar(bufnr, 'lsp_did_open', false) | return | endif
  var server: dict<any> = getbufvar(bufnr, 'lsp_server', {})
  if server->get('state', 'stopped') != 'ready' | return | endif
  if empty(v:completed_item) | return | endif
  util.Log('completion done: ' .. json_encode(v:completed_item))
  util.Log('completion event: ' .. json_encode(v:event))
  if !v:completed_item->has_key('user_data') || v:completed_item.user_data->type() != type({})
    return
  endif
  var edits: list<dict<any>> = get(v:completed_item, 'user_data', {})
    ->get('textEdits', [])
  if !empty(edits)
    util.ApplyEdits(bufnr, edits)
  endif
enddef
