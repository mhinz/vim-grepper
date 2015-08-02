if exists('g:loaded_grepper') || &compatible
  finish
endif
let g:loaded_grepper = 1

let s:initialized = 0
let s:slash = exists('+shellslash') && !&shellslash ? '\' : '/'

" s:error() {{{1
function! s:error(msg)
  echohl ErrorMsg
  echomsg a:msg
  echohl NONE
endfunction
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

" s:init() {{{1
function! s:init() abort
  let s:grepper = {
        \ 'setting': {},
        \ 'option': {
        \   'use_quickfix': 1,
        \   'do_open': 1,
        \   'do_switch': 1,
        \   'do_jump': 1,
        \   'programs': ['git', 'ag', 'pt', 'ack', 'grep', 'findstr'],
        \   'git':     { 'grepprg': 'git grep -n',              'grepformat': '%f:%l:%m'    },
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

  let ack     = index(s:grepper.option.programs, 'ack')
  let ackgrep = index(s:grepper.option.programs, 'ack-grep')

  if (ack >= 0) && (ackgrep >= 0)
    call remove(s:grepper.option.programs, ackgrep)
  endif

  let s:getfile = ['lgetfile', 'cgetfile']
  let s:open    = ['lopen',    'copen'   ]
  let s:grep    = ['lgrep',    'grep'    ]

  let s:qf = s:grepper.option.use_quickfix  " short convenience var
  let s:id = 0  " running job ID

  let s:initialized = 1
endfunction

" s:start() {{{1
function! s:start(bang, ...) abort
  if !s:initialized
    call s:init()
  endif

  if empty(s:grepper.option.programs)
    call s:error('No grep program found!')
    return
  endif

  let prog   = s:grepper.option.programs[0]
  let search = s:prompt(prog, a:0 ? a:1 : '')
  let s:grepper.option.do_jump = !a:bang

  if !empty(search)
    call s:run_program(search)
  endif
endfunction

" s:prompt() {{{1
function! s:prompt(prog, search)
  echohl Question
  call inputsave()
  let mapping = maparg('<plug>(GrepperNext)', 'c', '', 1)

  try
    cnoremap <plug>(GrepperNext) $$$mAgIc###<cr>
    let search = input(s:grepper.option[a:prog].grepprg .'> ', a:search,
          \ 'customlist,Complete_files')
    cunmap <plug>(GrepperNext)
  finally
    call inputrestore()
    call s:restore_mapping(mapping)
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

  if stridx(prog.grepprg, '$*') >= 0
    let [a, b] = split(prog.grepprg, '\V$*')
    let cmdline = printf('%s%s%s', a, a:search, b)
  else
    let cmdline = printf('%s %s', prog.grepprg, a:search)
  endif

  call s:set_settings()

  if has('nvim')
    if s:id
      silent! call jobstop(s:id)
      let s:id = 0
    endif

    let cmd = ['sh', '-c', cmdline]


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

  let grep = s:grep[s:qf]
  if !s:grepper.option.do_jump
    let grep .= '!'
  endif
  try
    execute 'silent' grep fnameescape(a:search)
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

" s:restore_mapping() {{{1
function! s:restore_mapping(mapping)
  if !empty(a:mapping)
    execute printf('%s %s%s%s%s %s %s',
          \ (a:mapping.noremap ? 'cnoremap' : 'cmap'),
          \ (a:mapping.silent  ? '<silent>' : ''    ),
          \ (a:mapping.buffer  ? '<buffer>' : ''    ),
          \ (a:mapping.nowait  ? '<nowait>' : ''    ),
          \ (a:mapping.expr    ? '<expr>'   : ''    ),
          \  a:mapping.lhs,
          \  a:mapping.rhs)
  endif
endfunction

" Complete_files() {{{1
function! Complete_files(lead, line, _)
  let [head, path] = s:extract_path(a:lead)
  " handle relative paths
  if empty(path) || (path =~ '\s$')
    return map(split(globpath('.'.s:slash, path.'*'), '\n'), 'head . "." . v:val[1:] . (isdirectory(v:val) ? s:slash : "")')
  " handle sub paths
  elseif path =~ '^.\/'
    return map(split(globpath('.'.s:slash, path[2:].'*'), '\n'), 'head . "." . v:val[1:] . (isdirectory(v:val) ? s:slash : "")')
  " handle absolute paths
  elseif path[0] == '/'
    return map(split(globpath(s:slash, path.'*'), '\n'), 'head . v:val[1:] . (isdirectory(v:val) ? s:slash : "")')
  endif
endfunction

" s:extract_path() {{{1
function! s:extract_path(string) abort
  let item = split(a:string, '.*\s\zs', 1)
  let len  = len(item)

  if     len == 0 | let [head, path] = ['', '']
  elseif len == 1 | let [head, path] = ['', item[0]]
  elseif len == 2 | let [head, path] = item
  else            | throw 'The unexpected happened!'
  endif

  return [head, path]
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
      " For normal Vim, this is handled by running either :grep or :grep!
      if has('nvim') && s:grepper.option.do_jump
        cfirst
      endif
    endif
    redraw!
    echo printf('Found %d matches.', size)
  endif
  silent! doautocmd <nomodeline> User Grepper
endfunction
" }}}

" s:operator() {{{1
function! s:operator(bang, type, ...) abort
  let selsave = &selection
  let regsave = @@
  let &selection = 'inclusive'

  if a:0
    silent execute "normal! gvy"
  elseif a:type == 'line'
    silent execute "normal! '[V']y"
  else
    silent execute "normal! `[v`]y"
  endif

  call s:start(a:bang, @@)

  let &selection = selsave
  let @@ = regsave
endfunction
" }}}

" s:jumper() {{{1
function! s:jumper(type, ...) abort
  if a:0
    call <sid>operator(0, a:type)
  else
    exe printf('call <sid>operator(0, a:type, %s)',
          \    join(map(range(1, a:0), '"a:".v:val'),
          \         ', '))
  endif
endfunction
" }}}

" s:nojump() {{{1
function! s:nojump(type, ...) abort
  if a:0
    call <sid>operator(1, a:type)
  else
    exe printf('call <sid>operator(1, a:type, %s)',
          \    join(map(range(1, a:0), '"a:".v:val'),
          \         ', '))
  endif
endfunction
" }}}

nnoremap <silent> <plug>(Grepper)        :call <sid>start(0)<cr>
nnoremap <silent> <plug>(Grepper!)       :call <sid>start(1)<cr>
xnoremap <silent> <plug>(Grepper)        :<c-u>call <sid>jumper(visualmode(), 1)<cr>
xnoremap <silent> <plug>(Grepper!)       :<c-u>call <sid>nojump(visualmode(), 1)<cr>

nnoremap <silent> <plug>(GrepperMotion)  :set opfunc=<sid>jumper<cr>g@
nnoremap <silent> <plug>(GrepperMotion!) :set opfunc=<sid>nojump<cr>g@
xnoremap <silent> <plug>(GrepperMotion)  :<c-u>call <sid>jumper(visualmode(), 1)<cr>
xnoremap <silent> <plug>(GrepperMotion!) :<c-u>call <sid>nojump(visualmode(), 1)<cr>

command! -nargs=0 -bang -bar Grepper call s:start(<bang>)
