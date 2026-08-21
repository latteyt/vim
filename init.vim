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
set autoread
set autowriteall
set hlsearch
set switchbuf=uselast
set directory=/tmp//
set clipboard=unnamedplus

filetype plugin indent on
syntax on

packadd! comment
packadd! hlyank
packadd! editorconfig
packadd! termdebug
packadd! matchit
packadd! osc52

packadd! dirvish
packadd! autopair
packadd! fuzzyfinder
packadd! acp

set clipboard=unnamedplus

if exists('$SSH_TTY')
  packadd osc52
  set clipmethod+=osc52
endif

augroup hackvim
  autocmd!
  autocmd CmdlineChanged [:/?] call wildtrigger()
  autocmd BufReadPost * silent! normal! g`"
  autocmd BufWritePre * call execute('keeppatterns :%s/\s\+$//e')
  autocmd FileType python setlocal tabstop=4 shiftwidth=4 expandtab
augroup END




iabbrev <expr> date`` strftime("%Y-%m-%d %H:%M")
iabbrev <expr> email`` "yangtao97@nudt.edu.cn"

def Ensure2Win(cmd: string)
  if winnr('$') < 2
    split
  endif
  exe (v:count == 0 ? '' : ':' .. string(v:count)) .. cmd
enddef

nnoremap [a <ScriptCmd>Ensure2Win("previous")<CR>
nnoremap ]a <ScriptCmd>Ensure2Win("next")<CR>
nnoremap [A <ScriptCmd>Ensure2Win("first")<CR>
nnoremap ]A <ScriptCmd>Ensure2Win("last")<CR>

nnoremap [b <ScriptCmd>Ensure2Win("bprevious")<CR>
nnoremap ]b <ScriptCmd>Ensure2Win("bnext")<CR>
nnoremap [B <ScriptCmd>Ensure2Win("bfirst")<CR>
nnoremap ]B <ScriptCmd>Ensure2Win("blast")<CR>

nnoremap [l <ScriptCmd>Ensure2Win("lprevious")<CR>
nnoremap ]l <ScriptCmd>Ensure2Win("lnext")<CR>
nnoremap [L <ScriptCmd>Ensure2Win("lfirst")<CR>
nnoremap ]L <ScriptCmd>Ensure2Win("llast")<CR>

nnoremap [q <ScriptCmd>Ensure2Win("cprevious")<CR>
nnoremap ]q <ScriptCmd>Ensure2Win("cnext")<CR>
nnoremap [Q <ScriptCmd>Ensure2Win("cfirst")<CR>
nnoremap ]Q <ScriptCmd>Ensure2Win("clast")<CR>

nnoremap [t <ScriptCmd>Ensure2Win("tprevious")<CR>
nnoremap ]t <ScriptCmd>Ensure2Win("tnext")<CR>
nnoremap [T <ScriptCmd>Ensure2Win("tfirst")<CR>
nnoremap ]T <ScriptCmd>Ensure2Win("tlast")<CR>

nnoremap [<C-Q> <ScriptCmd>Ensure2Win("cpfile")<CR>
nnoremap ]<C-Q> <ScriptCmd>Ensure2Win("cnfile")<CR>
nnoremap [<C-L> <ScriptCmd>Ensure2Win("lpfile")<CR>
nnoremap ]<C-L> <ScriptCmd>Ensure2Win("lnfile")<CR>

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

cnoreabbrev grep grep!


