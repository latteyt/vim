vim9script
if exists('g:loaded_fzf')
  finish
endif
g:loaded_fzf = v:true

command! -nargs=1 -complete=customlist,fzf#Complete Fd call fzf#Open(<q-args>)
