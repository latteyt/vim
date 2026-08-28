vim9script
if exists('g:loaded_acp')
  finish
endif
g:loaded_acp = v:true

# if empty(prop_type_get('acpTool'))
#   prop_type_add('acpTool', {highlight: 'Conceal'})
# endif

command! -nargs=? -complete=file ACP call acp#Chat(<q-args>)
command! -range -nargs=* ACPAsk call acp#Ask(<q-args>, <line1>, <line2>)
command! ACPClose call acp#Close()
command! ACPList call acp#List()

augroup acp_vim
  autocmd!
  autocmd VimLeave * call acp#Close()
augroup END



# command! -nargs=1 AcpSwitch call acp#Session_Switch(<q-args>)
# command! -nargs=1 AcpLoad call acp#Session_Load(<q-args>)
# command! -nargs=? AcpCloseSession call acp#Session_CloseSession(<q-args>)

# if get(g:, 'acp_map', 1)
#   nnoremap <leader>ao :AcpOpen<CR>
#   nnoremap <leader>ap :AcpPrompt<Space>
#   nnoremap <leader>ac :AcpCancel<CR>
# endif

