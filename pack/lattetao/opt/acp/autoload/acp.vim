vim9script

import 'client.vim' as client

var opencode = client.New(['opencode', 'acp'])


export def Ask(query: string, l1: number, l2: number)
  echomsg query == null_string
enddef


export def Close()
enddef


export def Chat(cwd: string)
  if opencode.state != 'DEAD'
    return
  endif

  client.Reset(opencode)
  if !client.Start(opencode, cwd ?? getcwd())
    echoerr "[ACP] client start failed"
    return
  endif

  var workflow: dict<any> = {
    INIT: {
      method: 'initialize',
      params: {
        protocolVersion: 1,
        clientCapabilities: { fs: { readTextFile: true, writeTextFile: true } },
        clientInfo: { name: 'acp-vim', title: 'ACP Vim', version: '0.1.0' },
      },
      next: 'LIST',
    },
    LIST: {
      method: 'session/list',
      params: (c) => ({ cwd: getbufvar(bufnr(c.bufname), 'cwd') }),
      on: (c, resp) => {
        var sessions: list<dict<any>> = resp->get('result', {})->get('sessions', [])
        if empty(sessions)
          return 'NEW'
        else
          setbufvar(bufnr(c.bufname), 'sessionId', sessions[0].sessionId)
          return 'LOAD'
        endif
      },
    },
    NEW: {
      method: 'session/new',
      params: (c) => ({ cwd: getbufvar(bufnr(c.bufname), 'cwd'), mcpServers: [] }),
      on: (c, resp) => {
        var sessionId: string = resp->get('result')->get('sessionId')
        setbufvar(bufnr(c.bufname), 'sessionId', sessionId)
        c.state = 'IDLE'
        return ''
      },
    },
    LOAD: {
      method: 'session/load',
      params: (c) => ({
        sessionId: getbufvar(bufnr(c.bufname), 'sessionId'),
        cwd: getbufvar(bufnr(c.bufname), 'cwd'),
        mcpServers: [],
      }),
      on: (c, resp) => {
        c.state = 'IDLE'
        return ''
      },
    },
  }
  client.Execute(opencode, workflow, 'INIT')

enddef
