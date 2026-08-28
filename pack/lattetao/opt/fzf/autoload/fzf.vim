vim9script

var filescache: list<string> = []
var job: job = null_job

def ResetCache()
  filescache = []
enddef


def EnsureCache()
  if empty(filescache)
    if job != null_job && job_status(job) == 'run'
      return
    endif
    autocmd CmdlineLeave : ++once call ResetCache()

    job = job_start('timeout 10 rg --files', {
      out_cb: (_: channel, m: string) => {
        filescache->add(m)
      },
      err_io: 'null',
    })
  endif
enddef

export def Complete(ArgLead: string, CmdLine: string, CursorPos: number): list<string>
  EnsureCache()
  return empty(ArgLead) ? filescache : matchfuzzy(filescache, ArgLead)
enddef

export def Open(arg: string)
  EnsureCache()
  var matches = matchfuzzy(filescache, arg)
  if empty(matches)
    echohl ErrorMsg | echo 'No match for: ' .. arg | echohl None
    return
  endif
  var target = matches[0]->substitute('/$', '', '')
  execute 'edit ' .. fnameescape(target)
enddef

