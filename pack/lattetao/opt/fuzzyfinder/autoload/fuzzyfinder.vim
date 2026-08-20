vim9script

var filescache: list<string> = []

def ResetCache()
  filescache = []
enddef

def EnsureCache()
  if empty(filescache)
    autocmd CmdlineLeave : ++once call ResetCache()

    filescache = systemlist('timeout 5 rg --files 2>/dev/null')
    var dirs: dict<bool> = {}
    for f in filescache
      var d = fnamemodify(f, ':h')
      while d != '' && d != '.'
        dirs[d] = v:true
        d = fnamemodify(d, ':h')
      endwhile
    endfor
    for d in keys(dirs)
      filescache->add(d .. '/')
    endfor
  endif
enddef

export def FuzzComplete(ArgLead: string, CmdLine: string, CursorPos: number): list<string>
  EnsureCache()
  return empty(ArgLead) ? filescache : matchfuzzy(filescache, ArgLead)
enddef

export def OpenFuzz(arg: string)
  EnsureCache()
  var matches = matchfuzzy(filescache, arg)
  if empty(matches)
    echohl ErrorMsg | echo 'No match for: ' .. arg | echohl None
    return
  endif
  var target = matches[0]->substitute('/$', '', '')
  execute 'edit ' .. fnameescape(target)
enddef

