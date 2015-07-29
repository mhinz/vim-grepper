" Variables {{{1
let s:prototype = {
      \ 'settings': {},
      \ 'option': {
      \   'use_quickfix': 1,
      \   'do_open': 1,
      \   'programs': ['git', 'ag', 'ack', 'grep'],
      \   'git': {
      \     'cmd': 'git grep -ne',
      \   },
      \   'ag': {
      \     'cmd': 'ag --vimgrep',
      \     'format': '%f:%l:%c:%m',
      \   },
      \   'ack': {
      \     'cmd': 'ack --nocolor --noheading --column',
      \     'format': '%f:%l:%c:%m',
      \   },
      \   'grep': {
      \     'cmd': 'grep -n $* /dev/null',
      \   }
      \ },
      \ 'process': {
      \   'args': '',
      \ },
      \ }

if exists('g:grepper')
  call extend(s:prototype.option, g:grepper)
endif

let s:getexpr = ['lgetexpr', 'cgetexpr']
let s:open    = ['lopen',    'copen'   ]
let s:grep    = ['lgrep!',   'grep!'   ]

let s:qf = s:prototype.option.use_quickfix  " short convenience var
let s:id = 0  " running job ID
" }}}

" s:on_stdout() {{{1
function! s:on_stdout(id, data) abort
  if empty(s:grepper.process.data)
    for d in a:data
      call insert(s:grepper.process.data, d)
    endfor
  else
    if empty(s:grepper.process.data[0])
      let s:grepper.process.data[0] = a:data[0]
    else
      let s:grepper.process.data[0] .= a:data[0]
    endif
    for d in a:data[1:]
      call insert(s:grepper.process.data, d)
    endfor
  endif
endfunction

" s:on_stderr() {{{1
function! s:on_stderr(id, data) abort
  echohl ErrorMsg
  echomsg 'STDERR: '. join(a:data)
  echohl NONE
endfunction

" s:on_exit() {{{1
function! s:on_exit() abort
  execute 'tabnext' s:grepper.process.tabpage
  execute s:grepper.process.window .'wincmd w'
  execute s:getexpr[s:qf] 'reverse(s:grepper.process.data[1:])'

  let s:id = 0
  call s:restore_settings()
  call s:finish_up()
endfunction
" }}}

" s:set_program() {{{1
function! s:set_program() abort
  call filter(s:grepper.option.programs, 'executable(v:val)')
  " TODO: check if empty
  let s:grepper.process.program = s:grepper.option.programs[0]

endfunction

" s:cycle_program() {{{1
function! s:cycle_program(search) abort
  " TODO: check length
  let s:grepper.option.programs =
        \ s:grepper.option.programs[1:-1] + [s:grepper.option.programs[0]]
  let s:grepper.process.program = s:grepper.option.programs[0]
  call s:prompt(a:search)
endfunction

" s:prompt() {{{1
function! s:prompt(search)
  let prog = s:grepper.option[s:grepper.process.program]
  echohl Identifier
  call inputsave()
  try
    cnoremap <leader>s $$$cYcLePlZ###<cr>
    let input = input(prog.cmd .'> ', a:search)
    cunmap <leader>s
  catch
    return
  finally
    call inputrestore()
    echohl NONE
  endtry
  if input =~# '\V$$$cYcLePlZ###\$'
    call histdel('input')
    return s:cycle_program(input[:-15])
  endif
  let s:grepper.process.args = input
endfunction

" s:run_program() {{{1
function! s:run_program()
  let prog = s:grepper.option[s:grepper.process.program]

  call s:set_settings()

  if has('nvim')
    if s:id
      call jobstop(s:id)
      let s:id = 0
    endif

    let cmd = ['sh', '-c'] + [prog.cmd .' '. s:grepper.process.args]
    let s:id = jobstart(cmd, extend(s:grepper, {
          \ 'process': {
          \   'data': [],
          \   'tabpage': tabpagenr(),
          \   'window': winnr(),
          \ },
          \ 'on_stdout': function('s:on_stdout'),
          \ 'on_stderr': function('s:on_stderr'),
          \ 'on_exit': function('s:on_exit') }))
    return
  endif

  try
    execute 'silent' s:grep[s:qf] fnameescape(s:grepper.process.args)
  finally
    call s:restore_settings()
  endtry

  call s:finish_up()
  redraw!
endfunction

" s:set_settings() {{{1
function! s:set_settings() abort
  let prog = s:grepper.option[s:grepper.process.program]

  let s:grepper.settings.t_ti = &t_ti
  let s:grepper.settings.t_te = &t_te
  set t_ti= t_te=

  let s:grepper.settings.grepprg = &grepprg
  let &grepprg = prog.cmd

  if has_key(prog, 'format')
    let s:grepper.settings.grepformat = &grepformat
    let &grepformat = prog.format
  endif
endfunction

" s:restore_settings() {{{1
function! s:restore_settings() abort
    let &grepprg = s:grepper.settings.grepprg

    if has_key(s:grepper.settings, 'grepformat')
      let &grepformat = s:grepper.settings.grepformat
    endif

    let &t_ti = s:grepper.settings.t_ti
    let &t_te = s:grepper.settings.t_te
endfunction

" s:finish_up() {{{1
function! s:finish_up() abort
  if empty(s:qf ? getqflist() : getloclist(0))
    echohl WarningMsg
    echomsg 'No matches.'
    echohl NONE
  else
    if s:grepper.option.do_open
      execute s:open[s:qf]
    endif
  endif
  silent! doautocmd <nomodeline> User Grepper
endfunction
" }}}

" start() {{{1
function! s:start() abort
  let s:executing = 1
  let s:grepper = copy(s:prototype)
  call s:set_program()
  call s:prompt('')
  if !empty(s:grepper.process.args)
    call s:run_program()
  endif
  let s:executing = 0
endfunction

command! -bar Grepper call s:start()
