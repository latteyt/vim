vim9script
if exists('g:loaded_llmcopy')
  finish
endif
g:loaded_llmcopy = v:true

if !&autoread
  set autoread
endif
if !&autowriteall
  set autowriteall
endif

g:default_opencode_url = 'http://localhost:4096'

command! -range -nargs=0 LLMCopy call llm#Copy(<line1>, <line2>)
command! -range -nargs=0 LLMSend call llm#Send(<line1>, <line2>)
command! -range -nargs=+ LLMAsk call llm#Ask(<q-args>, <line1>, <line2>)

xnoremap <silent> <leader>y :LLMCopy<CR>
xnoremap <silent> <leader>s :LLMSend<CR>


augroup llmcopy_checktime
  autocmd!
  autocmd TextChanged,TextChangedI,TextChangedP * call llm#Sync()
augroup END

llm#Sync()


if system(printf("curl -s --noproxy '*' -o /dev/null -w '%%{http_code}' --max-time 2 %s/config", g:default_opencode_url))->trim() != '200'
  if empty($TMUX)
    silent! system('tmux new-session -d -s opencode "opencode --port"')
  else
    silent! system(' tmux new-window -d "opencode --port"')
  endif
endif

