vim9script

export def Hijack()
  for info: dict<any> in getbufinfo()
    var dirpath: string = info.name
    if empty(dirpath) || !isdirectory(dirpath)
      continue
    endif

    if !bufloaded(info.bufnr)
      bufload(info.bufnr)
    endif

    # Preserve undo state while we rebuild buffer contents.
    var undolevels: number = getbufvar(info.bufnr, '&undolevels')
    deletebufline(info.bufnr, 1, '$')

    try
      readdirex(dirpath, '1', {sort: 'collate'})->foreach((idx, item) => {
        # item keys: group, perm, name, user, type, time, size
        var fullpath: string = dirpath == '/'
          ? $'/{item.name}'
          : $'{dirpath}/{item.name}'
        if item.type ==# 'dir'
          fullpath ..= '/'
        endif
        setbufline(info.bufnr, idx + 1, fullpath)

        var fsize: string = item.size >= 1024 * 1024 * 1024
          ? printf('%.1fG', item.size / 1024.0 / 1024 / 1024)
          : item.size >= 1024 * 1024
          ? printf('%.1fM', item.size / 1024.0 / 1024)
          : item.size >= 1024
          ? printf('%.1fK', item.size / 1024.0)
          : printf('%dB', item.size)
        var ftime: string = strftime('%Y/%m/%d %H:%M', item.time)
        var virt_text: string = printf('%s  %7s  %s', item.perm, fsize, ftime)

        prop_clear(idx + 1)
        prop_add(idx + 1, 0, {bufnr: info.bufnr, type: 'virtext', text: virt_text, text_align: 'right'})

        if item.type ==# 'linkd'
          var target: string = resolve(fullpath)
          var link_text: string = getftype(target) == 'dir'
            ? target .. '/'
            : target
          prop_add(idx + 1, 0, {bufnr: info.bufnr, type: 'virtext', text: ' -> ' .. link_text, text_align: 'after'})
        endif
      })
    catch
      echoerr $'Cannot read directory: {dirpath}'
    endtry

    setbufvar(info.bufnr, '&undolevels', undolevels)
    setbufvar(info.bufnr, '&autochdir', 0)
    setbufvar(info.bufnr, '&buftype', 'nofile')
    setbufvar(info.bufnr, '&bufhidden', 'wipe')
    setbufvar(info.bufnr, '&buflisted', 0)
    setbufvar(info.bufnr, '&swapfile', 0)
    setbufvar(info.bufnr, '&undofile', 0)
    setbufvar(info.bufnr, '&filetype', 'dirvish')
  endfor

  if &filetype == 'dirvish'
    execute($'lcd {expand('%:p')}')
    nnoremap <buffer> R <Cmd>call dirvish#Hijack()<CR>

    var oldfiles: list<string> = map(copy(v:oldfiles), (_, val) => fnamemodify(val, ':p'))
    var lines: list<string> = getline(1, "$")
    for oldfile in oldfiles
      # line is oldfile's prefix
      var idxes: list<number> = lines->copy()->map((idx, line)
            \ => stridx(oldfile, line) != -1 ? idx + 1 : -1)->filter((_, val) => val > 0)
      if !empty(idxes)
        cursor(idxes[0], 0)
        break
      endif
    endfor
  endif
enddef

# Toggle to the parent directory of the current buffer.
export def Toggle()
  var path: string = getbufinfo('%')[0].name
  if empty(path)
    return
  endif
  execute($'edit {fnamemodify(path, ':h')}')
enddef


