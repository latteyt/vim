vim9script
if exists('g:loaded_dirvish')
  finish
endif
g:loaded_dirvish = v:true

# Map "-" to toggle between a file and its parent directory.
if !empty(mapcheck('-', 'n'))
  echohl ErrorMsg | echomsg "keymap `-` is occupied" | echohl None
  finish
endif

# Disable netrw so dirvish takes over directory browsing.
g:loaded_netrw = v:true
g:loaded_netrwPlugin = v:true

# Virtual-text property for displaying file metadata (perm, size, time).
if empty(prop_type_get('virtext'))
  prop_type_add('virtext', {highlight: 'NonText'})
endif

# Hijack directory buffers as they are opened.
augroup DIRVISH
  autocmd!
  autocmd BufAdd * call timer_start(0, (_) => dirvish#Hijack())
augroup END

nnoremap - <Cmd>call dirvish#Toggle()<CR>

# Also hijack the current buffer on startup in case we entered a directory
# before the BufAdd autocommand had a chance to fire.
dirvish#Hijack()

