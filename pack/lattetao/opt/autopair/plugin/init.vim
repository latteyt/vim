vim9script
if exists('g:loaded_autopair')
  finish
endif
g:loaded_autopair = v:true

inoremap <expr> <bs> autopair#Delete("\<bs>")
inoremap <expr> <c-h> autopair#Delete("\<c-h>")
inoremap <expr> <c-w> autopair#Delete("\<c-w>")
inoremap <expr> <cr> autopair#CR("\<cr>")

inoremap <silent> ( <c-r>=autopair#Open("(")<cr>
inoremap <silent> { <c-r>=autopair#Open("{")<cr>
inoremap <silent> [ <c-r>=autopair#Open("[")<cr>
inoremap <silent> ) <c-r>=autopair#Close(")")<cr>
inoremap <silent> } <c-r>=autopair#Close("}")<cr>
inoremap <silent> ] <c-r>=autopair#Close("]")<cr>
inoremap <silent> ' <c-r>=autopair#OpenClose("'")<cr>
inoremap <silent> " <c-r>=autopair#OpenClose('"')<cr>




