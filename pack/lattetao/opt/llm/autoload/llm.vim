vim9script

var sync_timer: number = -1

export def Sync()
  if sync_timer != -1
    timer_stop(sync_timer)
  endif
  sync_timer = timer_start(&updatetime, (_) => {
    if &buftype == ''
      var view = winsaveview()
      silent! update
      silent! checktime
      winrestview(view)
    endif
  }, {'repeat': -1})
enddef

def GetTextPrompt(l1: number, l2: number): string
  if getbufvar('%', '&buftype') == ''
    var filepath: string = getbufinfo('%')[0].name
    var text: string = $"==={filepath}===\n"
    var width = len(string(l2))
    text = text .. getbufline('%', l1, l2)
      ->map((idx, line) => printf('%*d:%s', width, idx + l1, line))->join("\n")
    return text
  elseif getbufvar('%', '&buftype') == 'quickfix'
    var text: string = $"===Vim quickfix list (position references, NOT file content)===\n"
    text = text .. getbufline('%', l1, l2)
      ->join("\n")
    return text
  elseif getbufvar('%', '&buftype') == 'help'
    var text: string = $"===Vim help: {fnamemodify(bufname('%'), ':t')} (read-only reference, do NOT edit)===\n"
    text = text .. getbufline('%', l1, l2)
      ->join("\n")
    return text
  else
    var text: string = $"===Vim buffer: {bufname('%')} (non-file, do NOT edit/search, content inline)===\n"
    text = text .. getbufline('%', l1, l2)
      ->join("\n")
    return text
  endif
enddef

export def Copy(l1: number, l2: number)
  setreg('+', GetTextPrompt(l1, l2), 'l')
  setreg('*', GetTextPrompt(l1, l2), 'l')
enddef

def Post(body: dict<any>, Then: func = null_function)
  job_start(['curl', '-s', '-S', '--fail-with-body',
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', 'Accept: application/json',
    '-H', 'x-opencode-directory: ' .. getcwd(),
    '-d', json_encode(body),
    get(g:, 'opencode_url', g:default_opencode_url) .. "/tui/publish"],
  {
    err_cb: (ch, msg) => {
      echoerr msg
    },
    exit_cb: (j, status) => {
      if status != 0
        echoerr "opencode publish failed (exit " .. status .. ")"
      elseif Then != null_function
        Then()
      endif
    }
  })
enddef

export def Ask(query: string, l1: number, l2: number)
  var text: string = query .. "\n" .. GetTextPrompt(l1, l2)
  var body: dict<any> = {type: "tui.prompt.append", properties: {text: text}}
  Post(body, () => Post({type: "tui.command.execute", properties: {command: "prompt.submit"}}))
enddef

# RawSend
export def Send(l1: number, l2: number)
  var text: string = getbufline('%', l1, l2)->join("\n")
  var body: dict<any> = {type: "tui.prompt.append", properties: {text: text}}
  Post(body, () => Post({type: "tui.command.execute", properties: {command: "prompt.submit"}}))
enddef
