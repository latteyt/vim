if exists("b:current_syntax")
  finish
endif

syn case ignore

" ```lang 围栏内按对应语言高亮（含 markdown）
" fence 名 -> 语法文件名 的映射
let s:fenced = {
      \ 'md': 'markdown',
      \ 'python': 'python', 'py': 'python',
      \ 'bash': 'bash', 'sh': 'sh', 'shell': 'sh',
      \ 'javascript': 'javascript', 'js': 'javascript',
      \ 'typescript': 'typescript', 'ts': 'typescript',
      \ 'lua': 'lua', 'vim': 'vim',
      \ 'json': 'json', 'yaml': 'yaml', 'yml': 'yaml',
      \ 'html': 'html', 'css': 'css', 'sql': 'sql',
      \ 'c': 'c', 'cpp': 'cpp',
      \ 'go': 'go', 'rust': 'rust', 'rs': 'rust',
      \ 'java': 'java', 'ruby': 'ruby', 'rb': 'ruby',
      \ 'php': 'php',
      \ }
let s:included = {}
for s:fence in keys(s:fenced)
  let s:ft = s:fenced[s:fence]
  let s:cluster = 'AcpLang' . substitute(s:ft, '[^0-9A-Za-z_]', '_', 'g')
  if !has_key(s:included, s:ft)
    let s:synfile = 'syntax/' . s:ft . '.vim'
    if empty(globpath(&runtimepath, s:synfile))
      let s:included[s:ft] = 0
    else
      execute 'syntax include @' . s:cluster . ' ' . s:synfile
      unlet! b:current_syntax
      let s:included[s:ft] = 1
    endif
  endif
  if s:included[s:ft]
    let s:region = 'acpCode' . substitute(s:fence, '[^0-9A-Za-z_]', '_', 'g')
    execute 'syntax region ' . s:region . ' matchgroup=acpMarkdownFence start=''^```' . s:fence . '\>'' end=''^```\s*$'' contains=@' . s:cluster . ' keepend'
  endif
endfor
unlet! s:fenced s:included s:fence s:ft s:cluster s:synfile s:region

highlight default link acpMarkdownFence Delimiter

let b:current_syntax = "acpchat"
