" Variables {{{1
let s:prototype = {
      \ 'settings': {},
      \ 'option': {
      \   'use_quickfix': 1,
      \   'do_open': 1,
      \   'order': ['git', 'ag', 'grep'],
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
      \     'cmd': 'grep -Ri',
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
let s:grep    = ['lgrep',    'grep'    ]

let s:qf = s:prototype.option.use_quickfix  " short convenience var
let s:id = 0  " running job ID
" }}}

" s:prototype.set_program() {{{1
function! s:prototype.set_program() abort
  for program in self.option.order
    if executable(program)
      let self.process.program = program
      return
    endif
  endfor
endfunction

" s:prototype.prompt() {{{1
function! s:prototype.prompt() abort
  echohl Identifier
  call inputsave()
  let self.process.args = input(self.option[self.process.program].cmd .'> ')
  call inputrestore()
  echohl NONE
endfunction

" s:prototype.run_program() {{{1
function! s:prototype.run_program()
  let prog = self.option[self.process.program]

  call self.set_settings()

  if has('nvim')
    if s:id
      call jobstop(s:id)
      let s:id = 0
    endif

    let cmd = ['sh', '-c'] + [prog.cmd .' '. self.process.args]
    let s:id = jobstart(cmd, extend(self, {
          \ 'process': {
          \   'data': [],
          \   'tabpage': tabpagenr(),
          \   'window': winnr(),
          \ },
          \ 'on_stdout': self.on_stdout,
          \ 'on_stderr': self.on_stderr,
          \ 'on_exit': self.on_exit }))
    return
  endif

  try
    execute 'silent' s:grep[s:qf] fnameescape(self.process.args)
  finally
    call self.restore_settings()
  endtry

  call self.finish_up()
  redraw!
endfunction

" s:prototype.set_settings() {{{1
function! s:prototype.set_settings() abort
  let prog = self.option[self.process.program]

  let self.settings.t_ti = &t_ti
  let self.settings.t_te = &t_te
  set t_ti= t_te=

  let self.settings.grepprg = &grepprg
  let &grepprg = prog.cmd

  if has_key(prog, 'format')
    let self.settings.grepformat = &grepformat
    let &grepformat = prog.format
  endif
endfunction

" s:prototype.restore_settings() {{{1
function! s:prototype.restore_settings() abort
    let &grepprg = self.settings.grepprg

    if has_key(self.settings, 'grepformat')
      let &grepformat = self.settings.grepformat
    endif

    let &t_ti = self.settings.t_ti
    let &t_te = self.settings.t_te
endfunction

" s:prototype.finish_up() {{{1
function! s:prototype.finish_up() abort
  if empty(s:qf ? getqflist() : getloclist(0))
    echohl WarningMsg
    echomsg 'No matches.'
    echohl NONE
  else
    if self.option.do_open
      execute s:open[s:qf]
    endif
  endif

  silent! doautocmd <nomodeline> User Grepper
endfunction
" }}}

" s:prototype.on_stdout() {{{1
function! s:prototype.on_stdout(id, data) abort
  if empty(self.process.data)
    for d in a:data
      call insert(self.process.data, d)
    endfor
  else
    if empty(self.process.data[0])
      let self.process.data[0] = a:data[0]
    else
      let self.process.data[0] .= a:data[0]
    endif
    for d in a:data[1:]
      call insert(self.process.data, d)
    endfor
  endif
endfunction

" s:prototype.on_stderr() {{{1
function! s:prototype.on_stderr(id, data) abort
  echohl ErrorMsg
  echomsg 'STDERR: '. join(a:data)
  echohl NONE
endfunction

" s:prototype.on_exit() {{{1
function! s:prototype.on_exit() abort
  execute 'tabnext' self.process.tabpage
  execute self.process.window .'wincmd w'
  execute s:getexpr[s:qf] 'reverse(self.process.data[1:])'

  let s:id = 0
  call self.restore_settings()
  call self.finish_up()
endfunction
" }}}

" grepper#start() {{{1
function! grepper#start() abort
  let instance = copy(s:prototype)
  call instance.set_program()
  call instance.prompt()
  call instance.run_program()
endfunction
