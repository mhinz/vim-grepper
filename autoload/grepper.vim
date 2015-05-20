" Variables {{{1
let s:prototype = {
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
      \     'cmd': 'command grep -Ri',
      \   }
      \ },
      \ 'process': {
      \   'args': '',
      \   'callback': {
      \     'data': [],
      \   },
      \ }
      \ }

if exists('g:grepper')
  call extend(s:prototype.option, g:grepper)
endif

let s:getexpr = ['lgetexpr', 'cgetexpr']
let s:open    = ['lopen',    'copen'   ]
let s:grep    = ['lgrep',    'grep'    ]

let s:qf = s:prototype.option.use_quickfix
let s:o  = s:prototype.option.do_open
" }}}

" s:handle_window() {{{1
function! s:handle_window()
  if empty(s:qf ? getqflist() : getloclist(0))
    echohl WarningMsg
    echomsg 'No matches.'
    echohl NONE
  else
    if s:o
      execute s:open[s:qf]
    endif
  endif
endfunction
" }}}

" s:prototype.set_program() {{{1
function! s:prototype.set_program()
  for program in self.option.order
    if executable(program)
      let self.process.program = program
      return
    endif
  endfor
endfunction

" s:prototype.prompt() {{{1
function! s:prototype.prompt()
  echohl Identifier
  call inputsave()
  let self.process.args = input(self.option[self.process.program].cmd .'> ')
  call inputrestore()
  echohl NONE
endfunction

" s:prototype.run_program() {{{1
function! s:prototype.run_program()
  let prog = self.option[self.process.program]

  if has('nvim')
    let s:window = winnr()
    let s:tabpage = tabpagenr()
    let self.process.callback.data = []
    let cmd = ['sh', '-c'] + [prog.cmd .' '. self.process.args]
    let id = jobstart(cmd, self.process.callback)
    return
  endif

  let old_grepprg = &grepprg
  let &grepprg = prog.cmd
  if has_key(prog, 'format')
    let old_grepformat = &grepformat
    let &grepformat = prog.format
  endif
  try
    execute 'silent' s:grep[s:qf] fnameescape(self.process.args)
  finally
    let &grepprg = old_grepprg
    if exists('old_grepformat')
      let &grepformat = old_grepformat
      unlet old_grepformat
    endif
  endtry

  call s:handle_window()
endfunction
" }}}

" s:prototype.process.callback.on_stdout() {{{1
function! s:prototype.process.callback.on_stdout(id, data)
  if empty(self.data)
    for d in a:data
      call insert(self.data, d)
    endfor
  else
    if empty(self.data[0])
      let self.data[0] = a:data[0]
    else
      let self.data[0] .= a:data[0]
    endif
    for d in a:data[1:]
      call insert(self.data, d)
    endfor
  endif
endfunction

" s:prototype.process.callbacks.on_stderr() {{{1
function! s:prototype.process.callback.on_stderr(id, data)
  echohl ErrorMsg
  echomsg 'STDERR: '. join(a:data)
  echohl NONE
endfunction

" s:prototype.process.callbacks.on_exit() {{{1
function! s:prototype.process.callback.on_exit()
  execute 'tabnext' s:tabpage
  execute s:window .'wincmd w'
  execute s:getexpr[s:qf] 'reverse(self.data[1:])'
  call s:handle_window()
endfunction
" }}}

" grepper#start() {{{1
function! grepper#start()
  let instance = copy(s:prototype)
  call instance.set_program()
  call instance.prompt()
  call instance.run_program()
endfunction
