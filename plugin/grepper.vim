nnoremap <silent> <plug>(GrepperOperator) :set opfunc=grepper#operator<cr>g@
xnoremap <silent> <plug>(GrepperOperator) :<c-u>call grepper#operator(visualmode())<cr>

command! -nargs=* -bar -complete=customlist,grepper#complete Grepper call grepper#parse_flags(<q-args>)

if hasmapto('<plug>(GrepperOperator)')
  silent! call repeat#set("\<plug>(GrepperOperator)", v:count)
endif

let cmds = [
      \ ['GrepperAck',     'ack'    ],
      \ ['GrepperAg',      'ag'     ],
      \ ['GrepperFindstr', 'findstr'],
      \ ['GrepperGit',     'git'    ],
      \ ['GrepperGrep',    'grep'   ],
      \ ['GrepperRg',      'rg'     ],
      \ ['GrepperPt',      'pt'     ],
      \ ]

for [cmd, tool] in cmds
  if exists(':'.cmd) != 2
    execute 'command! -nargs=+ -complete=file' cmd
          \ 'Grepper -noprompt -tool' tool '-query <args>'
  endif
endfor
