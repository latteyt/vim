vim9script
if exists('b:current_syntax')
  finish
endif
b:current_syntax = "dirvish"

highlight! link PathHead String
highlight! link PathTail Directory
highlight! link HiddenPath NonText

syntax match PathHead =^.*\/\ze[^/]\+/\?$=
syntax match PathTail =[^/]\+/$=
syntax match HiddenPath =^.*\/\.[^/]\+/\?$= contains=PathHead
