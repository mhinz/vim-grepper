if exists('b:current_syntax')
  finish
endif

syntax sync fromstart

syntax region GrepperPath       start=/^/ matchgroup=GrepperPathBar end=/ |/
      \ contains=GrepperPathFile,GrepperPathSlash,GrepperPathBar keepend
syntax region GrepperPathFile   start=/\/\@1<=/ end=/.*/ contained
syntax match  GrepperPathSlash  /\// contained
syntax region GrepperMatch      start=/|\@1<= \zs/ end=/$/

highlight default link GrepperPath      Directory
highlight default link GrepperPathFile  Identifier
highlight default link GrepperPathSlash Delimiter
highlight default link GrepperPathBar   Delimiter
highlight default link GrepperMatch     NONE

let b:current_syntax = 'grepper'
