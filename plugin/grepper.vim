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
      \   'do_switch': 1,
      \   'do_jump': 0,
      \   'programs': ['git', 'ag', 'pt', 'ack', 'grep', 'findstr'],
      \   'git':     { 'grepprg': 'git grep -ne',             'grepformat': '%f:%l:%m'    },
      \   'ag':      { 'grepprg': 'ag --vimgrep',             'grepformat': '%f:%l:%c:%m' },
      \   'pt':      { 'grepprg': 'pt --nogroup',             'grepformat': '%f:%l:%m'    },
      \   'ack':     { 'grepprg': 'ack --noheading --column', 'grepformat': '%f:%l:%c:%m' },
      \   'grep':    { 'grepprg': 'grep -Rn $* .',            'grepformat': '%f:%l:%m'    },
      \   'findstr': { 'grepprg': 'findstr -rspnc:"$*" *',    'grepformat': '%f:%l:%m'    },
      \ },
      \ 'process': {
      \   'args': '',
      \ }}

if exists('g:grepper')
  call extend(s:grepper.option, g:grepper)
endif

call filter(s:grepper.option.programs, 'executable(v:val)')

let s:getfile = ['lgetfile', 'cgetfile']
let s:open    = ['lopen',    'copen'   ]
let s:grep    = ['lgrep!',   'grep!'   ]

let s:qf = s:grepper.option.use_quickfix  " short convenience var
let s:id = 0  " running job ID
" }}}

" s:on_stderr() {{{1
function! s:on_stderr(id, data) abort
  call s:error('STDERR: '. join(a:data))
endfunction

" s:on_exit() {{{1
function! s:on_exit() abort
  execute 'tabnext' s:grepper.process.tabpage
  execute s:grepper.process.window .'wincmd w'

  execute s:getfile[s:qf] s:grepper.process.tempfile
  call delete(s:grepper.process.tempfile)

  let s:id = 0
  call s:restore_settings()
  return s:finish_up(s:grepper.process.cmd)
endfunction
" }}}

" s:start() {{{1
function! s:start(...) abort
  let search = ''

  if empty(s:grepper.option.programs)
    call s:error('No grep program found!')
    return
  endif

  if a:0
    let regsave = @@
    normal! gvy
    let search = @@
    let @@ = regsave
  endif

  let prog = s:grepper.option.programs[0]
  let search = s:prompt(prog, search)

  if !empty(search)
    call s:run_program(search)
  endif
endfunction

" s:prompt() {{{1
function! s:prompt(prog, search)
  echohl Question
  call inputsave()

  try
    cnoremap <tab> $$$mAgIc###<cr>
    let search = input(s:grepper.option[a:prog].grepprg .'> ', a:search)
    cunmap <tab>
  finally
    call inputrestore()
    echohl NONE
  endtry

  if search =~# '\V$$$mAgIc###\$'
    call histdel('input')
    let s:grepper.option.programs =
          \ s:grepper.option.programs[1:-1] + [s:grepper.option.programs[0]]
    return s:prompt(s:grepper.option.programs[0], search[:-12])
  endif

  return search
endfunction

" s:run_program() {{{1
function! s:run_program(search)
  let prog = s:grepper.option[s:grepper.option.programs[0]]
  let cmdline = prog.grepprg .' '. a:search
  call s:set_settings()

  if has('nvim')
    if s:id
      silent! call jobstop(s:id)
      let s:id = 0
    endif

    let cmd = ['sh', '-c']

    if stridx(prog.grepprg, '$*') >= 0
      let [a, b] = split(prog.grepprg, '\V$*')
      let cmd += [a . a:search . b]
    else
      let cmd += [prog.grepprg .' '. a:search]
    endif

    let tempfile = fnameescape(tempname())
    if exists('*mkdir')
      silent! call mkdir(fnamemodify(tempfile, ':h'), 'p', 0600)
    endif
    let cmd[-1] .= ' >'. tempfile

    let s:id = jobstart(cmd, extend(s:grepper, {
          \ 'process': {
          \   'tabpage': tabpagenr(),
          \   'window': winnr(),
          \   'tempfile': tempfile,
          \   'cmd': cmdline,
          \ },
          \ 'on_stderr': function('s:on_stderr'),
          \ 'on_exit': function('s:on_exit') }))
    return
  endif

  try
    execute 'silent' s:grep[s:qf] fnameescape(a:search)
  finally
    call s:restore_settings()
  endtry

  call s:finish_up(cmdline)
endfunction

" s:set_settings() {{{1
function! s:set_settings() abort
  let prog = s:grepper.option[s:grepper.option.programs[0]]

  let s:grepper.setting.t_ti = &t_ti
  let s:grepper.setting.t_te = &t_te
  set t_ti= t_te=

  let s:grepper.setting.grepprg = &grepprg
  let &grepprg = prog.grepprg

  if has_key(prog, 'format')
    let s:grepper.setting.grepformat = &grepformat
    let &grepformat = prog.grepformat
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
function! s:finish_up(cmd) abort
  let size = len(s:qf ? getqflist() : getloclist(0))
  if size == 0
    execute s:qf ? 'cclose' : 'lclose'
    echomsg 'No matches found.'
  else
    if s:grepper.option.do_open
      execute (size > 10 ? 10 : size) s:open[s:qf]
      let &l:statusline = a:cmd
      if !s:grepper.option.do_switch
        wincmd p
      endif
      if s:grepper.option.do_jump
        cfirst
      endif
    endif
    redraw!
  endif
  silent! doautocmd <nomodeline> User Grepper
endfunction
" }}}

nnoremap <silent> <plug>Grepper :call <sid>start()<cr>
xnoremap <silent> <plug>Grepper :call <sid>start('visual')<cr>

command! -nargs=0 -bar Grepper call s:start()
