vim9script

export def Log(msg: string): void
  var f: string = get(g:, 'lsp_logfile', '/tmp/lsp.log')
  writefile([strftime('%Y-%m-%d %H:%M:%S') .. ' [lsp] ' .. msg], f, 'a')
enddef


export def ByteToUTF16(line: string, byte: number): number
  return line->utf16idx(byte, true)
enddef


export def UTF16ToByte(line: string, utf16: number): number
  return line->byteidxcomp(utf16, true)
enddef


export def PathToUri(path: string): string
  return 'file://' .. path->uri_encode()->substitute('%2F', '/', 'g')
enddef


export def UriToPath(uri: string): string
  return substitute(uri, '^file://', '', '')->uri_decode()
enddef


export def FsRoot(root_patterns: list<string>, filepath: string): string
  Log('FsRoot: ' .. root_patterns->json_encode() .. ' ' .. filepath)
  var dir: string = fnamemodify(filepath, ':p:h')
  for p in root_patterns
    var found: string = p =~ '/$'
      ? finddir(p->substitute('/$', '', ''), dir .. ';')
      : findfile(p, dir .. ';')
    if found != ''
      return fnamemodify(found, ':p:h')
    endif
  endfor
  return dir
enddef


export def ApplyEdits(bufnr: number, edits: list<dict<any>>): void
  if empty(edits) || !bufloaded(bufnr)
    return
  endif
  var sorted_edits: list<dict<any>> = edits->copy()->sort((a, b) => {
    return (b.range.start.line - a.range.start.line) != 0
      ? b.range.start.line - a.range.start.line
      : b.range.start.character - a.range.start.character
  })
  for edit in sorted_edits
    var start: dict<any> = edit.range.start
    var end: dict<any> = edit.range.end
    var newtext: string = edit.newText
    var lines: list<string> = getbufline(bufnr, start.line + 1, end.line + 1)
    var before: string = empty(lines) ? '' : strpart(lines[0], 0, start.character)
    var after: string = empty(lines) ? '' : strpart(lines[-1], end.character)
    var new_lines: list<string> = split(before .. newtext .. after, '\n', true)
    deletebufline(bufnr, start.line + 1, end.line + 1)
    var append_lnum: number = min([start.line, getbufinfo(bufnr)[0].linecount])
    appendbufline(bufnr, append_lnum, new_lines)
  endfor
  execute('undojoin')
enddef
