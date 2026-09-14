vim9script

import autoload 'lsp/util.vim' as util

var prop_types: list<string> = ['LspError', 'LspWarning', 'LspInfo', 'LspHint', 'LspDiagText']

export def Update(params: dict<any>): void
  if params->empty() | return | endif
  var path: string = util.UriToPath(params.uri)
  var bufnr: number = bufnr(path)
  if bufnr <= 0 || !bufloaded(bufnr)
    return
  endif
  sign_unplace('LspDiag', {buffer: bufnr})
  prop_remove({types: prop_types, all: true, bufnr: bufnr})
  var total: number = getbufinfo(bufnr)[0]->get('linecount', 0)
  for diag in get(params, 'diagnostics', [])
    var degree: number = get(diag, 'severity', 4) - 1
    var name: string = prop_types[degree]
    var lnum_x: number = diag.range.start.line + 1
    var lnum_y: number = diag.range.end.line + 1
    var line_x: string = getbufoneline(bufnr, lnum_x)
    var line_y: string = getbufoneline(bufnr, lnum_y)
    # utf16idx -> byteidx
    var col_x: number = line_x->byteidxcomp(diag.range.start.character, true) + 1
    var col_y: number = line_y->byteidxcomp(diag.range.end.character, true) + 1

    silent! sign_place(0, 'LspDiag', name, bufnr, {lnum: lnum_x, priority: 100 - degree})
    silent! prop_add(lnum_x, col_x, {end_lnum: lnum_y, end_col: col_y, type: name, bufnr: bufnr})

    var message: string = get(diag, 'message', '')
    if message != ''
      silent! prop_add(lnum_x, 0, {text: ' <-- ' .. message, text_align: 'after', type: 'LspDiagText', bufnr: bufnr})
    endif


  endfor
enddef
