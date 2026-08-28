vim9script

var logfile = '/tmp/opencode/acp_smoke.log'
var stop_reason: string = ''
var got_stop: bool = false

def Log(msg: string)
  writefile([msg], logfile, 'a')
enddef

def OnPromptResp(resp: dict<any>)
  var r = get(resp, 'result', {})
  stop_reason = get(r, 'stopReason', '')
  got_stop = true
  Log('STOP_REASON ' .. string(stop_reason))
enddef

mkdir('/tmp/opencode', 'p')
writefile([], logfile)
Log('=== acp smoke test ===')

packadd acp

var cwd = '/tmp/opencode/acp_smoke_cwd'
mkdir(cwd, 'p')
g:acp_cwd = cwd
g:AcpOnPromptResp = OnPromptResp

Log('STEP1 open: acp#Session_Open()')
acp#Session_Open()
Log('ready after open: ' .. acp#Ready())

var ready = false
var i = 0
while i < 200
  sleep 100m
  if acp#Ready()
    ready = true
    break
  endif
  i += 1
endwhile
Log('STATE_READY ' .. (ready ? 'true' : 'false') .. ' ready=' .. acp#Ready())

if !ready
  Log('RESULT FAIL')
  acp#Close()
  qa!
endif

Log('STEP2 prompt: acp#Session_Prompt("say hi")')
acp#Session_Prompt('say hi')

var chunk = false
var j = 0
while j < 600
  sleep 100m
  if !chunk
    var bnr = acp#CurrentBuf()
    var blines = getbufline(bnr, 1, '$')
    for l in blines
      if l != '' && l[: 1] != '> '
        chunk = true
        break
      endif
    endfor
  endif
  if chunk && got_stop
    break
  endif
  j += 1
endwhile

var bnr2 = acp#CurrentBuf()
var blines2 = getbufline(bnr2, 1, '$')
Log('AGENT_MESSAGE_CHUNK ' .. (chunk ? 'true' : 'false'))
Log('STOP_REASON_ARRIVED ' .. (got_stop ? 'true' : 'false') .. ' stop_reason=' .. string(stop_reason))
Log('BUFFER_LINE_COUNT ' .. len(blines2))
for l in blines2
  Log('BUF| ' .. l)
endfor

var pass = ready && chunk && got_stop
Log('RESULT ' .. (pass ? 'PASS' : 'FAIL'))

acp#Close()
Log('=== end ===')
qa!
