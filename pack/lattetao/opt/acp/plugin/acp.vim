vim9script
if exists('g:loaded_acp')
  finish
endif
g:loaded_acp = v:true

command! AcpOpen call acp#Ui_Open()
command! -nargs=+ AcpPrompt call acp#Session_Prompt(<q-args>)
command! AcpCancel call acp#Session_Cancel()
command! AcpClose call acp#Close()

if get(g:, 'acp_map', 1)
  nnoremap <leader>ao :AcpOpen<CR>
  nnoremap <leader>ap :AcpPrompt<Space>
  nnoremap <leader>ac :AcpCancel<CR>
endif

augroup acp_vim
  autocmd!
  autocmd VimLeave * call acp#Close()
augroup END
