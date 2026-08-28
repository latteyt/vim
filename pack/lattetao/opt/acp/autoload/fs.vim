vim9script

import 'client.vim' as client

export def ReadTextFile(c: dict<any>, id: number, params: dict<any>)
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
    client.Reply(c, id, { content: join(lines, "\n") })
  catch
    client.Error(c, id, -32000, v:exception)
  endtry

enddef

export def WriteTextFile(c: dict<any>, id: number, params: dict<any>)
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
    client.Reply(c, id, v:null)
  catch
    client.Error(c, id, -32000, v:exception)
  endtry
enddef
