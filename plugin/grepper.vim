nnoremap <silent> <plug>(GrepperOperator) :set opfunc=grepper#operator<cr>g@
xnoremap <silent> <plug>(GrepperOperator) :<c-u>call grepper#operator(visualmode())<cr>

command! -nargs=* -bar -complete=file Grepper call grepper#parse_flags(<q-args>)

if hasmapto('<plug>(GrepperOperator)')
  silent! call repeat#set("\<plug>(GrepperOperator)", v:count)
endif

let cmds = [
      \ ['Ack',     'ack'    ],
      \ ['Ag',      'ag'     ],
      \ ['Findstr', 'findstr'],
      \ ['GG',      'git'    ],
      \ ['Grep',    'grep'   ],
      \ ['Pt',      'pt'     ],
      \ ['Sift',    'sift'   ],
      \ ]

for [cmd, tool] in cmds
  if exists(':'.cmd) != 2
    execute 'command! -nargs=* -complete=file' cmd
          \ 'Grepper -noprompt -tool' tool '-query <args>'
  endif
endfor
