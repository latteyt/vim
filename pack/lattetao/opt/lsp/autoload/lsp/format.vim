vim9script

import autoload 'lsp/util.vim' as util


def OnFormat(bufnr: number, resp: dict<any>)
  util.Log("OnFormat " .. json_encode(resp))
  if bufnr('%') != bufnr | return | endif
  var edits: list<dict<any>> = resp->get('result', [])
  if edits->empty() | return | endif
  # restore the best cursor
  var pos: list<number> = getcurpos()
  util.ApplyEdits(bufnr, edits)
  update
  var line: string = getbufoneline('%', pos[1])
  pos[2] = min([line->len(), pos[2]])
  cursor([pos[1], pos[2]])
enddef


export def Request()
  var bufnr: number = bufnr('%')
  if !getbufvar(bufnr, 'lsp_did_open', false) | return | endif
  var server: dict<any> = getbufvar(bufnr, 'lsp_server', {})
  if server->get('state', 'stopped') != 'ready' | return | endif

  if getbufvar(bufnr, '&readonly', true) | return | endif
  listener_flush(bufnr)

  var filepath: string = getbufinfo(bufnr)[0]->get('name', '')
  if filepath->empty() | return | endif

  var tabSize: number = getbufvar(bufnr, '&shiftwidth') > 0 ?
    getbufvar(bufnr, '&shiftwidth') : getbufvar(bufnr, '&tabstop')
  var params: dict<any> = {
    textDocument: {uri: util.PathToUri(filepath)},
    options: {
      tabSize: tabSize,
      insertSpaces: !!getbufvar(bufnr, '&expandtab')
    },
  }

  util.Log('FormatRequest ' .. json_encode(params))

  ch_sendexpr(server.channel, {
    method: 'textDocument/formatting',
    params: params,
  }, {callback: (ch: channel, resp: dict<any>) => OnFormat(bufnr, resp)})
enddef

