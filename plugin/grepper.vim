nnoremap <silent> <plug>(GrepperOperator) :set opfunc=grepper#operator<cr>g@
xnoremap <silent> <plug>(GrepperOperator) :<c-u>call grepper#operator(visualmode())<cr>

command! -nargs=* -bar -bang -complete=file Grepper call grepper#parse_command(<bang>0, <f-args>)
