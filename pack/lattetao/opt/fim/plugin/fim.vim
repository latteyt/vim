vim9script

if exists('g:loaded_fim')
  finish
endif
g:loaded_fim = v:true

g:default_cancel_keys = [
  "\<BS>", "\<C-h>", "\<Del>", "\<C-w>", "\<C-u>"
]


if empty(prop_type_get('FimVT'))
  prop_type_add('FimVT', {'highlight': 'Conceal'})
endif

augroup fim_plugin
  autocmd!
  autocmd KeyInputPre * call fim#OnKeyInput()
  autocmd InsertCharPre * call fim#OnInsertChar()
  autocmd InsertLeave * call fim#OnInsertLeave()
augroup END

imap <script><silent><nowait><expr> <Tab> fim#HasFimVT() ? fim#AcceptWord() : "\<Tab>"
imap <script><silent><nowait><expr> <C-j> fim#HasFimVT() ? fim#AcceptAll() : "\<C-j>"
imap <script><silent><nowait><expr> <C-l> fim#HasFimVT() ? fim#AcceptLine() : "\<C-l>"
imap <script><silent><nowait><expr> <C-p> fim#HasFimVT() ? fim#Next() : "\<C-p>"




