" s:warn() {{{1
function! s:warn(msg)
  echohl WarningMsg
  echomsg a:msg
  echohl NONE
endfunction

" s:error() {{{1
function! s:error(msg)
  echohl ErrorMsg
  echomsg a:msg
  echohl NONE
endfunction
" }}}

" Variables {{{1
let s:grepper = {
      \ 'setting': {},
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
      \     'cmd': 'grep -Rn $* .'
      \   }
      \ },
      \ 'process': {
      \   'args': '',
      \ }}

if exists('g:grepper')
  call extend(s:grepper.option, g:grepper)
endif

call filter(s:grepper.option.programs, 'executable(v:val)')
if empty(s:grepper.option.programs)
  call s:error('No program found!')
  finish
endif

let s:getexpr = ['lgetexpr', 'cgetexpr']
let s:open    = ['lopen',    'copen'   ]
let s:grep    = ['lgrep!',   'grep!'   ]

let s:qf = s:grepper.option.use_quickfix  " short convenience var
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
  call s:error('STDERR: '. join(a:data))
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

" s:start() {{{1
function! s:start(...) abort
  let search = ''

  if a:0
    let regsave = @@
    normal! gvy
    let search = @@
    let @@ = regsave
  endif

  let prog = s:get_program()
  let search = s:prompt(prog, search)

  if !empty(search)
    call s:run_program(prog, search)
  endif
endfunction

" s:get_program() {{{1
function! s:get_program()
  if s:grepper.option.programs[0] == 'git'
        \ && empty(finddir('.git', getcwd().';'))
    return s:cycle_program('')
  endif

  return s:grepper.option.programs[0]
endfunction

" s:cycle_program() {{{1
function! s:cycle_program(args) abort
  let s:grepper.option.programs =
        \ s:grepper.option.programs[1:-1] + [s:grepper.option.programs[0]]

  if s:grepper.option.programs[0] == 'git'
        \ && empty(finddir('.git', getcwd().';'))
    return s:cycle_program(a:args)
  endif

  return s:prompt(s:grepper.option.programs[0], a:args)
endfunction

" s:prompt() {{{1
function! s:prompt(prog, search)
  echohl Identifier
  call inputsave()

  try
    cnoremap <tab> $$$mAgIc###<cr>
    let search = input(s:grepper.option[a:prog].cmd .'> ', a:search)
    cunmap <tab>
  finally
    call inputrestore()
    echohl NONE
  endtry

  if search =~# '\V$$$mAgIc###\$'
    call histdel('input')
    return s:cycle_program(search[:-12])
  endif

  return search
endfunction

" s:run_program() {{{1
function! s:run_program(prog, search)
  let prog = s:grepper.option[a:prog]

  call s:set_settings(a:prog)

  if has('nvim')
    if s:id
      call jobstop(s:id)
      let s:id = 0
    endif

    let cmd = ['sh', '-c']

    if stridx(prog.cmd, '$*') >= 0
      let [a, b] = split(prog.cmd, '\V$*')
      let cmd += [a . a:search . b]
    else
      let cmd += [prog.cmd .' '. a:search]
    endif

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
    execute 'silent' s:grep[s:qf] fnameescape(a:search)
  finally
    call s:restore_settings()
  endtry

  call s:finish_up()
  redraw!
endfunction

" s:set_settings() {{{1
function! s:set_settings(prog) abort
  let prog = s:grepper.option[a:prog]

  let s:grepper.setting.t_ti = &t_ti
  let s:grepper.setting.t_te = &t_te
  set t_ti= t_te=

  let s:grepper.setting.grepprg = &grepprg
  let &grepprg = prog.cmd

  if has_key(prog, 'format')
    let s:grepper.setting.grepformat = &grepformat
    let &grepformat = prog.format
  endif
endfunction

" s:restore_settings() {{{1
function! s:restore_settings() abort
    let &grepprg = s:grepper.setting.grepprg

    if has_key(s:grepper.setting, 'grepformat')
      let &grepformat = s:grepper.setting.grepformat
    endif

    let &t_ti = s:grepper.setting.t_ti
    let &t_te = s:grepper.setting.t_te
endfunction

" s:finish_up() {{{1
function! s:finish_up() abort
  let size = len(s:qf ? getqflist() : getloclist(0))
  if size == 0
    call s:warn('No matches.')
  else
    if s:grepper.option.do_open
      execute (size > 10 ? 10 : size) s:open[s:qf]
    endif
  endif
  doautocmd <nomodeline> User Grepper
endfunction
" }}}

nnoremap <silent> <plug>Grepper :call <sid>start()<cr>
xnoremap <silent> <plug>Grepper :call <sid>start('visual')<cr>

command! -nargs=0 -bar Grepper call s:start()
