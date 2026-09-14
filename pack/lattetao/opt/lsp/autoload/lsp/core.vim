vim9script

import autoload 'lsp/util.vim' as util
import autoload 'lsp/diagnostic.vim' as diagnostic

var servers: dict<dict<any>> = {}
var diag_timer: number = -1


# 通用 workflow 状态机：
# flow 是 dict<step, func(ctx, Next)>
#   Next : 转移函数 Next(next)，同步/异步均可调用；Next('') 结束
# 每个状态转移由 Go 闭包统一记录 Log。
def Run(server: dict<any>, flow: dict<any>, cur: string): void
  if cur == '' || !has_key(flow, cur) | return | endif
  var Step: func(dict<any>, func(string)) = flow[cur]
  var Go: func(string) = (nxt: string) => {
    util.Log($'state {cur} -> {nxt == "" ? "END" : nxt}')
    Run(server, flow, nxt)
  }
  Step(server, Go)
enddef

def Spawn(server: dict<any>, Next: func(string)): void
  var opts: dict<any> = {
    in_mode: 'lsp', out_mode: 'lsp', err_mode: 'nl',
    out_cb: (ch: channel, msg: dict<any>) => OnData(ch, msg),
    err_cb: (ch: channel, msg: string) => util.Log('stderr: ' .. msg),
    exit_cb: (job: job, status: number) => {
      util.Log($'job {server.cmd} exited status={status}')
      server.state = "stopped"
      server.pending = []
    }
  }
  server.job = job_start(server['cmd'], opts)
  server.channel = job_getchannel(server.job)
  if job_status(server.job) != 'run' || ch_status(server.channel) != 'open'
    util.Log('spawn: job start failed')
    server.error = 'job start failed: ' .. join(server.cmd)
    Next('ERR')
    return
  endif
  server.state = 'starting'
  util.Log('spawn: started ' .. join(server.cmd) .. ' root=' .. server.rootpath)
  Next('INIT')
enddef

def Init(server: dict<any>, Next: func(string)): void
  var params: dict<any> = {
    processId: getpid(),
    rootUri: util.PathToUri(server.rootpath),
    rootPath: server.rootpath,
    workspaceFolders: [{ uri: util.PathToUri(server.rootpath), name: server.rootpath }],
    capabilities: {
      general: { positionEncodings: ['utf-16'] },
      workspace: { workspaceFolders: true },
      textDocument: {
        synchronization: { dynamicRegistration: false, willSave: false, willSaveWaitUntil: false, didSave: false },
        completion: { completionItem: { snippetSupport: false, deprecatedSupport: true } },
        publishDiagnostics: { relatedInformation: false },
      },
    },
    clientInfo: { name: 'lattetao/lsp', version: '0.0.1' },
  }
  ch_sendexpr(server.channel, { method: 'initialize', params: params }, {
    callback: (ch: channel, resp: dict<any>) => {
      if resp->has_key('error')
        util.Log('init: initialize returned error')
        server.error = resp.error
        Next('ERR')
        return
      endif
      var result: dict<any> = resp->get('result', {})
      util.Log('initialized ' .. json_encode(result))
      server.capabilities = result->get('capabilities', {})
      ch_sendexpr(server.channel, { method: 'initialized', params: {} })
      ch_sendexpr(server.channel, { method: 'workspace/didChangeConfiguration', params: { settings: server.settings }})
      server.state = 'ready'
      Next('READY')
    },
  })
enddef


def PullDiagnostics(server: dict<any>, bufnr: number): void
  var filepath: string = getbufinfo(bufnr)[0]->get('name', '')
  if filepath->empty() | return | endif
  var uri: string = util.PathToUri(filepath)
  ch_sendexpr(server.channel, {
    method: 'textDocument/diagnostic',
    params: { textDocument: { uri: uri } },
  }, {callback: (ch: channel, resp: dict<any>) => {
    if resp->has_key('error') || !resp->has_key('result') | return | endif
    var report: dict<any> = resp.result
    if report->get('kind', '') == 'full'
      diagnostic.Update({ uri: uri, diagnostics: report->get('items', []) })
    endif
  }})
enddef


def OnChange(bufnr: number)
  if !getbufvar(bufnr, 'lsp_did_open', false) | return | endif
  var server: dict<any> = getbufvar(bufnr, 'lsp_server', {})
  if server->get('state', 'stopped') != 'ready' | return | endif

  # var text: string = getbufline(bufnr, 1, '$')->join("\n")
  # text = getbufvar(bufnr, '&eol') ? text .. "\n" : text
  # var contentChanges: list<dict<any>> = [{ text: text }]

  var newTexts: list<string> = getbufline(bufnr, 1, '$')
  var oldTexts: list<string> = getbufvar(bufnr, 'lsp_cached_context', [])
  var contentChanges: list<dict<any>>
  if !getbufvar(bufnr, '&eol')
    contentChanges = [{ text: newTexts->join("\n") }]
  else
    var diffs: list<dict<number>> = diff(oldTexts, newTexts, { output: 'indices' })
    if diffs->len() > 1
      contentChanges = [{ text: newTexts->join("\n") .. "\n" }]
    elseif diffs->len() == 1
      var hunk: dict<number> = diffs[0]
      var start: dict<any> = { line: hunk.from_idx, character: 0 }
      var end: dict<any> = { line: hunk.from_idx + hunk.from_count, character: 0 }
      var last_idx: number = hunk.to_idx + hunk.to_count - 1
      var text: string = hunk.to_count == 0 ? ""
        : newTexts[hunk.to_idx : last_idx]->join("\n") .. "\n"
      contentChanges = [{range: {start: start, end: end}, text: text}]
    else
      contentChanges = []
    endif
  endif
  setbufvar(bufnr, "lsp_cached_context", newTexts)
  if contentChanges->empty() | return | endif

  var filepath: string = getbufinfo(bufnr)[0]->get('name', '')
  if filepath->empty() | return | endif

  var params: dict<any> = {
    textDocument: {
      uri: util.PathToUri(filepath),
      version: getbufvar(bufnr, 'changedtick'),
    },
    contentChanges: contentChanges,
  }
  util.Log('textDocument/didChange ' .. json_encode(params))
  ch_sendexpr(server.channel, { method: 'textDocument/didChange', params: params })

  if !server.capabilities->has_key('diagnosticProvider') | return | endif
  timer_stop(diag_timer)
  diag_timer = timer_start(500, (_: number) => PullDiagnostics(server, bufnr))

enddef


def OnOpen(server: dict<any>, bufnr: number): void
  if !bufloaded(bufnr) | bufload(bufnr) | endif
  var filepath: string = getbufinfo(bufnr)[0]->get('name')
  var texts: list<string> = getbufline(bufnr, 1, '$')
  var text: string = texts->join("\n")
  var params: dict<any> = {
    textDocument: {
      uri: util.PathToUri(filepath),
      languageId: getbufvar(bufnr, '&filetype'),
      version: getbufvar(bufnr, 'changedtick'),
      text: getbufvar(bufnr, '&eol') ? text .. "\n" : text,
    },
  }
  util.Log("textDocument/didOpen " .. json_encode(params))
  ch_sendexpr(server.channel, {
    method: 'textDocument/didOpen',
    params: params,
  })
  setbufvar(bufnr, 'lsp_did_open', true)
  setbufvar(bufnr, 'lsp_cached_context', texts)
  setbufvar(bufnr, 'lsp_server', server)
  setbufvar(bufnr, '&autocomplete', false)
  setbufvar(bufnr, '&eol', true)
  # DocumentSync
  var Id: number = listener_add((_, _, _, _, _) => {
    OnChange(bufnr)
  }, bufnr)
  var Ids: list<number> = getbufvar(bufnr, 'lsp_listeners', [])
  setbufvar(bufnr, 'lsp_listeners', Ids + [Id])
  # buffer local keymap
  execute($'buffer {bufnr}')
  nnoremap <buffer> gd <Cmd>LSPGotoDefinition<CR>
  nnoremap <buffer> gD <Cmd>LSPGotoTypeDefinition<CR>
  nnoremap <buffer> gi <Cmd>LSPGotoImplementation<CR>

enddef

def Ready(server: dict<any>, Next: func(string)): void
  util.Log($'ready: flush pending buffers')
  server.pending->foreach((_, bufnr) => OnOpen(server, bufnr))
  server.pending = []
  Next('')
enddef

def RemoveBufListener(bnr: number): void
  for listenerId in getbufvar(bnr, 'lsp_listeners', [])
    listener_remove(listenerId)
  endfor
  setbufvar(bnr, 'lsp_listeners', [])
enddef


export def Attach(bufnr: number): void
  if getbufvar(bufnr, 'lsp_did_open', false) | return | endif
  if getbufvar(bufnr, '&buftype') != '' | return | endif

  var filepath: string = getbufinfo(bufnr)[0]->get('name', '')
  if filepath->empty() | return | endif
  var filetype: string = getbufvar(bufnr, '&filetype')
  if !g:lsp_config->has_key(filetype) | return | endif
  var root_patterns: list<string> = g:lsp_config->get(filetype, {})->get('root_patterns', [])
  var rootpath: string = util.FsRoot(root_patterns, filepath)
  if rootpath->empty() | return | endif

  if !servers->has_key(filetype)
    servers[filetype] = {}
  endif
  if !servers[filetype]->has_key(rootpath)
    # state: stopped/starting/ready/error
    servers[filetype][rootpath] = {
      job: null_job, channel: null_channel, state: 'stopped',
      pending: [],
      rootpath: rootpath,
      capabilities: {},
      cmd: g:lsp_config[filetype]['cmd'],
      settings: g:lsp_config[filetype]->get('settings', {}),
      textDocumentSync: 0,
      cachedBufferContent: {},
    }
    util.Log($'Attach: {filepath}, root={rootpath}, filetype={filetype}')
  endif


  var flow: dict<any> = {
    SPAWN: (server: dict<any>, Next: func(string)) => Spawn(server, Next),
    INIT: (server: dict<any>, Next: func(string)) => Init(server, Next),
    READY: (server: dict<any>, Next: func(string)) => Ready(server, Next),
    ERR: (server: dict<any>, Next: func(string)) => {
      server.state = 'error'
      server.pending = []
      if ch_status(server.channel) == 'open'
        ch_close(server.channel)
      endif
      if job_status(server.job) == 'run'
        job_stop(server.job)
      endif
      util.Log('init failed: ' .. json_encode(server->get('error', {})))
      Next('')
      echoerr 'LSP init failed: ' .. json_encode(server->get('error', {}))
    },
  }

  var server: dict<any> = servers[filetype][rootpath]
  if server.state != 'error'
    server.pending->add(bufnr)
  endif
  if server.state == 'ready'
    Run(server, flow, 'READY')
  elseif server.state == 'stopped'
    Run(server, flow, 'SPAWN')
  endif
enddef

export def Detach(bufnr: number): void
  if !getbufvar(bufnr, 'lsp_did_open', false) | return | endif
  var server: dict<any> = getbufvar(bufnr, 'lsp_server', {})
  if server->get('state', 'stopped') != 'ready' | return | endif

  var filepath: string = getbufinfo(bufnr)[0].name # if no exists, just crash
  util.Log('closing ' .. util.PathToUri(filepath))
  ch_sendexpr(server.channel, {
    method: 'textDocument/didClose',
    params: { textDocument: { uri: util.PathToUri(filepath) } },
  })
  setbufvar(bufnr, 'lsp_did_open', false)
  setbufvar(bufnr, 'lsp_cached_context', [])
  setbufvar(bufnr, 'lsp_server', {})
  getbufvar(bufnr, 'lsp_listeners', [])
    ->foreach((_, Id) => listener_remove(Id))
  setbufvar(bufnr, 'lsp_listeners', [])
enddef


export def StopAll(): void
  for info in getbufinfo()
    Detach(info.bufnr)
  endfor
  for ft in values(servers)
    for server in values(ft)
      if ch_status(server.channel) == 'open'
        ch_close(server.channel)
      endif
      if job_status(server.job) == 'run'
        job_stop(server.job)
      endif
    endfor
  endfor
enddef


export def OnData(ch: channel, msg: dict<any>): void
  util.Log('RECV ' .. json_encode(msg))
  if has_key(msg, 'id') && has_key(msg, 'method')
    # server 请求：id 可能是字符串，ch_sendexpr 会 E475，直接 sendraw 返回 null
    var resp: dict<any> = { jsonrpc: '2.0', id: msg.id, result: v:null }
    var body: string = json_encode(resp)
    ch_sendraw(ch, $"Content-Length: {strlen(body)}\r\n\r\n{body}")
    return
  endif
  var method: string = get(msg, 'method', '')
  if method == 'textDocument/publishDiagnostics'
    diagnostic.Update(get(msg, 'params', {}))
  endif
enddef
