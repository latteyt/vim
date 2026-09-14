vim9script
if exists('g:loaded_autopair')
  finish
endif
g:loaded_autopair = v:true


def ClosePair(key: string): string
  return strcharpart(getline('.'), charcol('.') - 1, 1) == key ?
    "\<c-g>u\<right>" : key
enddef


def ExpandPair(): string
  return index(["()", "{}", "[]"], strcharpart(getline('.'), charcol('.') - 2, 2)) > -1 ?
    "\<Cr>\<C-o>O" : "\<Cr>"
enddef

inoremap <silent> ( ()<C-g>u<left>
inoremap <silent> { {}<C-g>u<left>
inoremap <silent> [ []<C-g>u<left>

inoremap <silent> <expr> ) ClosePair(")")
inoremap <silent> <expr> } ClosePair("}")
inoremap <silent> <expr> ] ClosePair("]")

inoremap <silent> <expr> <CR> ExpandPair()










