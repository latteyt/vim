vim9script

var logfile = '/tmp/opencode/acp_perm.log'
var got_stop: bool = false

def Log(msg: string)
  writefile([msg], logfile, 'a')
enddef

def OnPromptResp(resp: dict<any>)
  got_stop = true
  Log('STOP ' .. string(get(get(resp, 'result', {}), 'stopReason', '')))
enddef

mkdir('/tmp/opencode', 'p')
writefile([], logfile)
Log('=== acp permission diff test ===')

packadd acp

var cwd = '/tmp/opencode/acp_perm_cwd'
mkdir(cwd, 'p')
writefile(['old content line'], cwd .. '/hello.txt')
g:acp_cwd = cwd
g:AcpOnPromptResp = OnPromptResp

Log('STEP1 open')
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
Log('READY ' .. (ready ? 'true' : 'false'))

if !ready
  Log('RESULT FAIL')
  acp#Close()
  qa!
endif

Log('STEP2 prompt to edit hello.txt')
acp#Session_Prompt('在 hello.txt 末尾追加一行：hello from agent。直接改文件。')

var got_perm = false
var j = 0
while j < 600
  sleep 100m
  if !empty(acp#Perm_Pending())
    got_perm = true
    break
  endif
  if got_stop
    break
  endif
  j += 1
endwhile
Log('GOT_PERM ' .. (got_perm ? 'true' : 'false'))

var diff_ok = false
if got_perm
  var pend = acp#Perm_Pending()
  var old_buf = get(pend, 'old_buf', -1)
  var new_buf = get(pend, 'new_buf', -1)
  var old_lines = getbufline(old_buf, 1, '$')
  var new_lines = getbufline(new_buf, 1, '$')
  Log('OLD_BUF ' .. join(old_lines, ' / '))
  Log('NEW_BUF ' .. join(new_lines, ' / '))
  var old_ok = join(old_lines, "\n") =~ 'old content line'
  var new_ok = join(new_lines, "\n") =~ 'hello from agent'
  diff_ok = old_ok && new_ok
  Log('DIFF_BUFS ' .. (diff_ok ? 'true' : 'false'))

  Log('STEP3 confirm once')
  acp#Perm_Confirm('once')
  Log('PENDING_CLEARED ' .. (empty(acp#Perm_Pending()) ? 'true' : 'false'))
endif

# 等 agent 完成写文件
var k = 0
while k < 600 && !got_stop
  sleep 100m
  k += 1
endwhile
Log('STOP_ARRIVED ' .. (got_stop ? 'true' : 'false'))

var fcontent = readfile(cwd .. '/hello.txt')
var file_ok = join(fcontent, "\n") =~ 'hello from agent'
Log('FILE ' .. join(fcontent, ' / '))
Log('FILE_OK ' .. (file_ok ? 'true' : 'false'))

var pass = ready && got_perm && diff_ok && file_ok && got_stop
Log('RESULT ' .. (pass ? 'PASS' : 'FAIL'))

acp#Close()
Log('=== end ===')
qa!
