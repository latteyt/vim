vim9script
if exists('g:loaded_fuzzyfinder')
  finish
endif
g:loaded_fuzzyfinder = v:true

command! -nargs=1 -complete=customlist,fuzzyfinder#FuzzComplete FuzzyFinder call fuzzyfinder#OpenFuzz(<q-args>)
cnoreabbrev fzf FuzzyFinder
