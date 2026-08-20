vim9script

var mappings: dict<dict<string>>  = {
  '(': { pair: '()', neigh_pattern: '^[^\\]' },
  '[': { pair: '[]', neigh_pattern: '^[^\\]' },
  '{': { pair: '{}', neigh_pattern: '^[^\\]' },
  ')': { pair: '()', neigh_pattern: '^[^\\]' },
  ']': { pair: '[]', neigh_pattern: '^[^\\]' },
  '}': { pair: '{}', neigh_pattern: '^[^\\]' },
  '"': { pair: '""', neigh_pattern: '^[^\\]' },
  "'": { pair: "''", neigh_pattern: '^[^%a\\]'},
}

export def Open(key: string): string
  var neigh: string = strcharpart("\r" .. getline('.') .. "\n", charcol('.') - 1, 2)
  var neigh_pattern: string = mappings[key].neigh_pattern
  if !empty(matchstr(neigh, neigh_pattern))
    return mappings[key].pair .. "\<c-g>u\<left>"
  else
    return key
  endif
enddef

export def Close(key: string): string
  var neigh: string = strcharpart("\r" .. getline('.') .. "\n", charcol('.') - 1, 2)
  var neigh_pattern: string = mappings[key].neigh_pattern
  var right: string = strcharpart("\r" .. getline('.') .. "\n", charcol('.'), 1)
  if !empty(matchstr(neigh, neigh_pattern)) && right == key
    return "\<c-g>u\<right>"
  else
    return key
  endif
enddef


export def OpenClose(key: string): string
  var neigh: string = strcharpart("\r" .. getline('.') .. "\n", charcol('.') - 1, 2)
  var neigh_pattern: string = mappings[key].neigh_pattern
  var right: string = strcharpart("\r" .. getline('.') .. "\n", charcol('.'), 1)
  if !empty(matchstr(neigh, neigh_pattern)) && right == key
    return "\<c-g>u\<right>"
  else
    return Open(key)
  endif
enddef



export def Delete(key: string): string
  var neigh: string = strcharpart("\r" .. getline('.') .. "\n", charcol('.') - 1, 2)
  var pairs: list<string> = copy(mappings)->values()->map((_, it) => it.pair)
  if index(pairs, neigh) >= 0
    return key .. "\<del>"
  else
    return key
  endif
enddef

export def CR(key: string): string
  var neigh: string = strcharpart("\r" .. getline('.') .. "\n", charcol('.') - 1, 2)
  var pairs: list<string> = copy(mappings)->values()->map((_, it) => it.pair)
  if index(pairs, neigh) >= 0
    return key .. "\<c-o>O"
  else
    return key
  endif
enddef



