vim9script

var logfile = '/tmp/opencode/acp_multi.log'
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
Log('=== acp multi-session test ===')

packadd acp

var cwd = '/tmp/opencode/acp_multi_cwd'
mkdir(cwd, 'p')
g:acp_cwd = cwd
g:AcpOnPromptResp = OnPromptResp

Log('STEP1 open first session')
acp#Session_Open()

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
Log('FIRST_READY ' .. (ready ? 'true' : 'false') .. ' ready=' .. acp#Ready())
var sid1 = acp#CurrentSession()
Log('SID1 ' .. sid1)

if !ready
  Log('RESULT FAIL')
  acp#Close()
  qa!
endif

Log('STEP2 new second session')
acp#Session_New()

var sid2 = sid1
var j = 0
while j < 100
  sleep 100m
  sid2 = acp#CurrentSession()
  if sid2 != sid1
    break
  endif
  j += 1
endwhile
Log('SID2 ' .. sid2)
Log('SID2_DIFF ' .. (sid2 != sid1 ? 'true' : 'false'))
Log('SESSION_COUNT ' .. acp#SessionCount())
var count2 = acp#SessionCount()

Log('STEP3 switch back to first session')
acp#Session_Switch(sid1)
Log('AFTER_SWITCH ' .. acp#CurrentSession())
Log('SWITCH_OK ' .. (acp#CurrentSession() == sid1 ? 'true' : 'false'))

Log('STEP4 prompt on first session')
acp#Session_Prompt('say hello in one word')

var chunk = false
var got = false
var k = 0
while k < 600
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
    got = true
    break
  endif
  k += 1
endwhile
Log('CHUNK ' .. (chunk ? 'true' : 'false') .. ' STOP ' .. (got_stop ? 'true' : 'false'))

Log('STEP5 list sessions')
acp#Session_List()

# 等待 list 响应处理
var l = 0
while l < 50
  sleep 100m
  l += 1
endwhile

Log('STEP6 close second session')
acp#Session_CloseSession(sid2)

var m = 0
while m < 50
  sleep 100m
  m += 1
endwhile
Log('AFTER_CLOSE_COUNT ' .. acp#SessionCount())
Log('CURRENT_AFTER_CLOSE ' .. acp#CurrentSession())
var count_after = acp#SessionCount()

var pass = ready && sid2 != sid1 && count2 == 2 && acp#CurrentSession() == sid1 && chunk && got_stop && count_after == 1
Log('RESULT ' .. (pass ? 'PASS' : 'FAIL'))

acp#Close()
Log('=== end ===')
qa!
