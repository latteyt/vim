vim9script
g:python_recommended_style = 1
g:loaded_netrw = v:true
g:mapleader = "\\"
g:tex_flavor = "latex"

colorscheme catppuccin
set background=dark
set termguicolors

set cmdheight=2
set signcolumn=yes
set cursorline
set relativenumber
set number
set showmatch
set shiftwidth=2
set expandtab
set softtabstop=2
set scrolloff=10
set smoothscroll
set list
set listchars=leadmultispace:\|+,tab:\ >
set mouse=
set completeopt=menuone,noinsert,popup,fuzzy
set autocomplete
set undofile
set undodir=$MYVIMDIR/undo
set viminfo='500,<2000,s100,h,:500,/500,@500,%50,r/tmp,!,n$MYVIMDIR/viminfo
set viewoptions=cursor,curdir,folds
set jumpoptions=stack
set grepprg=rg\ --vimgrep\ --smart-case
set grepformat=%f:%l:%c:%m
set wildmode=noselect:lastused,full
set wildoptions=fuzzy,pum
set laststatus=2
set shortmess+=F
set updatetime=2000
set updatecount=20
set autoread
set hlsearch
set switchbuf=uselast
set directory=/tmp//
set clipboard=unnamedplus
set smartcase

filetype plugin indent on
syntax on

packadd! comment
packadd! hlyank
packadd! editorconfig
packadd! termdebug
packadd! matchit

packadd! dirvish
packadd! autopair
packadd! fzf
packadd! lsp

if exists('$DEEPSEEK_API_KEY')
  packadd! llm
  packadd! fim
endif


set clipboard=unnamedplus

if exists('$SSH_TTY')
  packadd! osc52
  set clipmethod+=osc52
endif

augroup hackvim
  autocmd!
  autocmd CmdlineChanged [:/?] call wildtrigger()
  autocmd BufReadPost * silent! exe 'normal! g`"'
  autocmd VimLeavePre * bufdo keeppatterns :%s/\s\+$//e | update
  autocmd FileType python setlocal tabstop=4 shiftwidth=4 expandtab
augroup END




iabbrev <expr> date`` strftime("%Y-%m-%d %H:%M")
iabbrev <expr> email`` "yangtao97@nudt.edu.cn"

nnoremap <silent> [a :<C-U>exe v:count1 . "previous"<CR>
nnoremap <silent> ]a :<C-U>exe v:count1 . "next"<CR>
nnoremap <silent> [A :<C-U>exe v:count1 . "first"<CR>
nnoremap <silent> ]A :<C-U>exe v:count1 . "last"<CR>

nnoremap <silent> [b :<C-U>exe v:count1 . "bprevious"<CR>
nnoremap <silent> ]b :<C-U>exe v:count1 . "bnext"<CR>
nnoremap <silent> [B :<C-U>exe v:count1 . "bfirst"<CR>
nnoremap <silent> ]B :<C-U>exe v:count1 . "blast"<CR>

nnoremap <silent> [l :<C-U>exe v:count1 . "lprevious"<CR>
nnoremap <silent> ]l :<C-U>exe v:count1 . "lnext"<CR>
nnoremap <silent> [L :<C-U>exe v:count1 . "lfirst"<CR>
nnoremap <silent> ]L :<C-U>exe v:count1 . "llast"<CR>

nnoremap <silent> [q :<C-U>exe v:count1 . "cprevious"<CR>
nnoremap <silent> ]q :<C-U>exe v:count1 . "cnext"<CR>
nnoremap <silent> [Q :<C-U>exe v:count1 . "cfirst"<CR>
nnoremap <silent> ]Q :<C-U>exe v:count1 . "clast"<CR>

nnoremap <silent> [t :<C-U>exe v:count1 . "tprevious"<CR>
nnoremap <silent> ]t :<C-U>exe v:count1 . "tnext"<CR>
nnoremap <silent> [T :<C-U>exe v:count1 . "tfirst"<CR>
nnoremap <silent> ]T :<C-U>exe v:count1 . "tlast"<CR>

nnoremap <silent> [<C-Q> :<C-U>exe v:count1 . "cpfile"<CR>
nnoremap <silent> ]<C-Q> :<C-U>exe v:count1 . "cnfile"<CR>
nnoremap <silent> [<C-L> :<C-U>exe v:count1 . "lpfile"<CR>
nnoremap <silent> ]<C-L> :<C-U>exe v:count1 . "lnfile"<CR>

nnoremap <silent> [<C-T> :<C-U>exe v:count1 . "ptprevious"<CR>
nnoremap <silent> ]<C-T> :<C-U>exe v:count1 . "ptnext"<CR>

nnoremap <silent> [<Space> :<C-U>put!=repeat(nr2char(10), v:count1)<CR>']+
nnoremap <silent> ]<Space> :<C-U>put =repeat(nr2char(10), v:count1)<CR>'[-


cnoreabbrev W! w!
cnoreabbrev Q! q!
cnoreabbrev Qall! qall!
cnoreabbrev Wq wq
cnoreabbrev Wa wa
cnoreabbrev wQ wq
cnoreabbrev WQ wq
cnoreabbrev W w
cnoreabbrev Q q
cnoreabbrev Qall qall



