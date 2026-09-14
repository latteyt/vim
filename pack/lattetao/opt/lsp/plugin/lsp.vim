vim9script

import autoload 'lsp/core.vim' as core
import autoload 'lsp/complete.vim' as complete

if !exists('g:lsp_config')
  g:lsp_config = {
    go: {
      cmd: ['gopls'],
      root_patterns: ['go.mod', '.git/'],
      settings: {}
    },
    c: {
      cmd: ['clangd', '--background-index', '--all-scopes-completion', '--clang-tidy', '--completion-style=detailed'],
      root_patterns: ['compile_commands.json', 'Makefile', '.git/', 'CMakeLists.txt'],
      settings: {}
    },
    cpp: {
      cmd: ['clangd', '--background-index', '--all-scopes-completion', '--clang-tidy', '--completion-style=detailed'],
      root_patterns: ['compile_commands.json', 'Makefile', '.git/', 'CMakeLists.txt'],
      settings: {}
    },
    python: {
      cmd: ['basedpyright-langserver', '--stdio'],
      root_patterns: ['pyproject.toml', 'pyrightconfig.json', '.venv/', '.git/'],
      settings: {}
    },
    typescript: {
      cmd: ['tsc', '--lsp', '--stdio'],
      root_patterns: ['package-lock.json', 'tsconfig.json', 'jsconfig.json', 'package.json', '.git/'],
      settings: {}
    },
    lua: {
      cmd: ['lua-language-server'],
      root_patterns: ['.luarc.json', '.git/'],
      settings: {}
    },
    rust: {
      cmd: ['rust-analyzer'],
      root_patterns: ['Cargo.toml', '.git/'],
      settings: {}
    },
  }
endif

if !exists('g:lsp_logfile')
  g:lsp_logfile = '/tmp/lsp.log'
endif

highlight default link LspErrorSign ErrorMsg
highlight default link LspWarningSign WarningMsg
highlight default link LspInfoSign MoreMsg
highlight default link LspHintSign Comment

highlight default link LspErrorHighlight Error
highlight default link LspWarningHighlight WarningMsg
highlight default link LspInfoHighlight MoreMsg
highlight default link LspHintHighlight Comment

highlight default link LspDiagVirtualText Comment

sign_define('LspError', {text: 'E', texthl: 'LspErrorSign'})
sign_define('LspWarning', {text: 'W', texthl: 'LspWarningSign'})
sign_define('LspInfo', {text: 'I', texthl: 'LspInfoSign'})
sign_define('LspHint', {text: 'H', texthl: 'LspHintSign'})

prop_type_add('LspError', {highlight: 'LspErrorHighlight'})
prop_type_add('LspWarning', {highlight: 'LspWarningHighlight'})
prop_type_add('LspInfo', {highlight: 'LspInfoHighlight'})
prop_type_add('LspHint', {highlight: 'LspHintHighlight'})
prop_type_add('LspDiagText', {highlight: 'LspDiagVirtualText'})

highlight! link PmenuDeprecated Pmenu
highlight! PmenuDeprecated gui=strikethrough cterm=strikethrough

highlight! link PmenuDeprecatedSel PmenuSel
highlight! PmenuDeprecatedSel gui=strikethrough cterm=strikethrough

command! LSPGotoDefinition call lsp#jump#Request("textDocument/definition")
command! LSPGotoTypeDefinition call lsp#jump#Request("textDocument/typeDefinition")
command! LSPGotoImplementation call lsp#jump#Request("textDocument/implementation")
command! LSPFormat call lsp#format#Request()

augroup lsp
  autocmd!
  autocmd BufNewFile,BufReadPost * core.Attach(str2nr(expand('<abuf>')))
  autocmd BufUnload * core.Detach(str2nr(expand('<abuf>')))
  autocmd VimLeavePre * core.StopAll()
  autocmd InsertCharPre * complete.OnInsertChar(str2nr(expand('<abuf>')))
  autocmd KeyInputPre * complete.OnKeyInput(str2nr(expand('<abuf>')))
  autocmd CompleteDone * complete.OnDone(str2nr(expand('<abuf>')))
  autocmd CursorHold * lsp#format#Request()
augroup END



