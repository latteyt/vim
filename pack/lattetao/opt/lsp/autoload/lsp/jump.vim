vim9script

import autoload 'lsp/util.vim' as util

def Normalize(loc: dict<any>): dict<any>
  var filename: string = util.UriToPath(loc.uri)
  var lnum: number = loc.range.start.line + 1
  var text: string = readfile(filename)->get(lnum - 1, '')
  var col: number = text->byteidxcomp(loc.range.start.character, true) + 1
  return {filename: filename, lnum: lnum, col: col, text: text}
enddef

def OnJump(resp: dict<any>)
  util.Log("OnJump " .. json_encode(resp))
  var results: list<dict<any>> = resp->get('result', [])
    ->map((_, loc) => Normalize(loc))
  if results->empty() | return | endif
  setloclist(win_getid(), [], 'r', {title: 'LSP Jump', items: results})
  lfirst
enddef

export def Request(method: string)
  var bufnr: number = bufnr('%')
  if !getbufvar(bufnr, 'lsp_did_open', false) | return | endif
  var server: dict<any> = getbufvar(bufnr, 'lsp_server', {})
  if server->get('state', 'stopped') != 'ready' | return | endif
  listener_flush(bufnr)

  var lnum: number = line('.')
  var col: number = col('.')
  var cline: string = getline('.')

  var filepath: string = getbufinfo(bufnr)[0]->get('name', '')
  if filepath->empty() | return | endif

  var params: dict<any> = {
    textDocument: {uri: util.PathToUri(filepath)},
    position: {line: lnum - 1, character: cline->utf16idx(col - 1, true)},
  }
  util.Log('JumpRequest ' .. json_encode(params))

  ch_sendexpr(server.channel, {
    method: method, params: params,
  }, {callback: (ch: channel, resp: dict<any>) => OnJump(resp)})
enddef



