vim9script
# 脚本级状态：补全文本与触发时快照，供异步回调读写。
#
#

var curl_job: job = null_job
var debounce_timer: number = -1

var context: dict<any> = {
  bufnr: -1,
  lnum: -1,
  col: -1,
  text: '',
}


# 防抖间隔（毫秒）
const DEBOUNCE_MS = 1000
# 最大生成 token 数
const MAX_TOKENS = 256
# 请求超时（秒）
const REQUEST_TIMEOUT_S = 20

def Log(tag: string, data: string)
  var line = strftime('%Y-%m-%d %H:%M:%S') .. ' [' .. tag .. '] ' .. data
  writefile([line], '/tmp/fim.log', 'a')
enddef


def OnOut(ch: channel, msg: string)
  Log("RECV", msg)
  context.text = json_decode(msg)['choices'][0]['text']
enddef

# 渲染虚拟文本：第一行 inline 在光标后，后续行 below。
def Render()

  if empty(context.text) || context.bufnr != bufnr('%') || context.lnum != line('.') || context.col != col('.')
    return
  endif

  if mode() !~ '^i' | return | endif
  if pumvisible() | feedkeys("\<C-e>", 'n') | endif

  echomsg json_encode(context.text)
  var lines: list<string> = split(context.text, "\r\n\\=\\|\n", true)
  prop_add(context.lnum, context.col, {'type': 'FimVT', 'text': lines[0]})
  for line in lines[1 : ]
    # FIXME `text_prop` BUG: 0-with is not allowed
    prop_add(context.lnum, 0, {'type': 'FimVT', 'text': line ?? "\n\n\n", 'text_align': 'below'})
  endfor
enddef

def OnExit(j: job, status: number)
  if status == 0 && mode() =~ '^i'
    Render()
  endif
enddef

export def Complete()
  if debounce_timer > 0
    timer_stop(debounce_timer)
  endif
  debounce_timer = timer_start(DEBOUNCE_MS, (_) => {
    Request()
  }, {repeat: 1})
enddef

export def OnKeyInput()
  if index(get(g:, "cancel_keys", g:default_cancel_keys), v:char) >= 0
    var bufnr: number = str2nr(expand('<abuf>'))
    prop_remove({'type': 'FimVT', 'bufnr': bufnr, 'all': true})
  endif
enddef

export def OnInsertChar()
  var bufnr: number = str2nr(expand('<abuf>'))
  prop_remove({'type': 'FimVT', 'bufnr': bufnr, 'all': true})
  Complete()
enddef

export def OnInsertLeave()
  var bufnr: number = str2nr(expand('<abuf>'))
  prop_remove({'type': 'FimVT', 'bufnr': bufnr, 'all': true})
  context = {bufnr: -1, lnum: -1, col: -1, text: ''}
  if curl_job != null_job
    job_stop(curl_job)
  endif
  if debounce_timer > 0
    timer_stop(debounce_timer)
  endif
enddef


def Request()
  if curl_job != null_job
    job_stop(curl_job)
  endif

  context = {bufnr: bufnr('%'), lnum: line('.'), col: col('.'), text: ''}

  # 其他文件 buffer（buftype 为空）的内容，作为全局上下文前缀
  var before: list<string> = []
  for info in getbufinfo({'buflisted': true})
    if info.bufnr == context.bufnr || getbufvar(info.bufnr, '&buftype') != ''
      continue
    endif
    before->add($'// file: {(info.name ?? '[No Name]')} filetype: {(getbufvar(info.bufnr, '&filetype') ?? 'none')}')
    before->extend(getbufline(info.bufnr, 1, '$'))
    before->add('')
  endfor

  var info = getbufinfo('%')[0]
  before->add($'// file: {(info.name ?? '[No Name]')} filetype: {(getbufvar(info.bufnr, '&filetype') ?? 'none')}')
  before->extend(getbufline(context.bufnr, 1, context.lnum - 1))

  var after = getbufline(context.bufnr, context.lnum + 1, '$')
  var curline = getbufoneline(context.bufnr, context.lnum)
  before->add(strpart(curline, 0, context.col - 1))
  after->insert(strpart(curline, context.col - 1))
  var body = {
    'model': 'deepseek-v4-pro',
    'prompt': join(before, "\n"), 'suffix': join(after, "\n"),
    'max_tokens': MAX_TOKENS
  }


  curl_job = job_start(
    ['curl', '-sS', '--max-time', string(REQUEST_TIMEOUT_S),
    'https://api.deepseek.com/beta/completions',
    '-H', 'Content-Type: application/json',
    '-H', 'Authorization: Bearer ' .. $DEEPSEEK_API_KEY,
    '-d', json_encode(body)],
    {'out_mode': 'raw', 'out_cb': OnOut, 'exit_cb': OnExit})
enddef



export def HasFimVT(): bool
  return !empty(prop_find({'type': 'FimVT', 'bufnr': bufnr('%'), 'lnum': line('.'), 'col': col('.')}, 'f'))
enddef

export def AcceptAll(): string
  timer_start(0, (_) => {
    prop_remove({'type': 'FimVT', 'bufnr': bufnr('%'), 'all': true})
    var line = getline(context.lnum)
    var head = strpart(line, 0, context.col - 1)
    var tail = strpart(line, context.col - 1)
    var lines = split(context.text, "\n", true)
    lines[0] = head .. lines[0]
    lines[len(lines) - 1] ..= tail
    setline(context.lnum, lines[0])
    append(context.lnum, lines[1 : ])

    context.lnum += len(lines) - 1
    context.col = len(lines[len(lines) - 1]) - len(tail) + 1
    context.text = ''
    cursor(context.lnum, context.col)
    Render()
  }, {repeat: 1})
  return ''
enddef

export def AcceptWord(): string
  timer_start(0, (_) => {
    prop_remove({'type': 'FimVT', 'bufnr': bufnr('%'), 'all': true})
    var end = matchend(context.text, '[^[:space:]]\+')
    # 前导分隔符（空格/Tab/换行）+ 第一个 word 一起插入
    var insert_text = strpart(context.text, 0, end)
    var line = getline(context.lnum)
    var head = strpart(line, 0, context.col - 1)
    var tail = strpart(line, context.col - 1)
    var ilines = split(insert_text, "\n", true)
    ilines[0] = head .. ilines[0]
    ilines[len(ilines) - 1] ..= tail
    setline(context.lnum, ilines[0])
    append(context.lnum, ilines[1 : ])

    context.lnum += len(ilines) - 1
    context.col = len(ilines[len(ilines) - 1]) - len(tail) + 1
    context.text = strpart(context.text, end)

    Log("TAB", json_encode(context.text))
    cursor(context.lnum, context.col)
    Render()
  }, {repeat: 1})
  return ''
enddef

# 核心逻辑：接受一行（含换行符）；无换行时等同 AcceptAll
export def AcceptLine(): string
  timer_start(0, (_) => {
    prop_remove({'type': 'FimVT', 'bufnr': bufnr('%'), 'all': true})

    var nl = stridx(context.text, "\n")
    var insert_text = nl >= 0 ? strpart(context.text, 0, nl + 1) : context.text

    var line = getline(context.lnum)
    var head = strpart(line, 0, context.col - 1)
    var tail = strpart(line, context.col - 1)
    var ilines = split(insert_text, "\n", true)
    ilines[0] = head .. ilines[0]
    ilines[len(ilines) - 1] ..= tail
    setline(context.lnum, ilines[0])
    append(context.lnum, ilines[1 : ])

    context.lnum += len(ilines) - 1
    context.col = len(ilines[len(ilines) - 1]) - len(tail) + 1
    context.text = strpart(context.text, strlen(insert_text))
    cursor(context.lnum, context.col)

    Log("LINE", json_encode(context.text))
    Render()
  }, {repeat: 1})
  return ''
enddef

# 核心逻辑：换候选
export def Next(): string
  timer_start(0, (_) => {
    prop_remove({'type': 'FimVT', 'bufnr': bufnr('%'), 'all': true})
    Request()
  }, {repeat: 1})
  return ''
enddef




