" s:prototype {{{1
let s:prototype = {
      \ 'program': {
      \   'order': ['git', 'ag', 'grep'],
      \   'git': {
      \     'cmd': 'git grep -ne',
      \   },
      \   'ag': {
      \     'cmd':    'ag --vimgrep',
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
      \   'cmd': '',
      \   'args': '',
      \   'callback': {
      \     'data': [],
      \   },
      \ }
      \ }

if exists('g:grepper')
  call extend(s:prototype.program, g:grepper)
endif

" s:prototype.process.callback.on_stdout() {{{1
function! s:prototype.process.callback.on_stdout(id, data)
  echomsg 'DATA: '. string(a:data)
  for d in a:data
    call insert(self.data, d)
  endfor
endfunction

" s:prototype.process.callbacks.on_stderr() {{{1
function! s:prototype.process.callback.on_stderr(id, data)
  echohl ErrorMsg
  echomsg 'STDERR: '. join(a:data)
  echohl NONE
endfunction

" s:prototype.process.callbacks.on_exit() {{{1
function! s:prototype.process.callback.on_exit()
  if empty(self.data)
    echohl WarningMsg
    echomsg 'No matches.'
    echohl NONE
  else
    lgetexpr reverse(self.data)
    lopen
  endif
endfunction

" s:prototype.prompt() {{{1
function! s:prototype.prompt()
  echohl Identifier
  call inputsave()
  let self.process.args = input(self.program[self.process.program].cmd .'> ')
  call inputrestore()
  echohl NONE
endfunction

" s:prototype.set_program() {{{1
function! s:prototype.set_program()
  for program in self.program.order
    if executable(program)
      let self.process.program = program
      return
    endif
  endfor
endfunction

" s:prototype.run_program() {{{1
function! s:prototype.run_program()
  let prog = self.program[self.process.program]

  if has('nvim')
    let self.process.callback.data = []
    let self.process.callback.window = winnr()
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
    execute 'silent lgrep' fnameescape(self.process.args)
    if empty(getloclist(0))
      echohl WarningMsg
      echomsg 'No matches.'
      echohl NONE
    else
      lopen
    endif
  finally
    let &grepprg = old_grepprg
    if exists('old_grepformat')
      let &grepformat = old_grepformat
      unlet old_grepformat
    endif
  endtry
endfunction
" }}}

" grepper#start() {{{1
function! grepper#start()
  let instance = copy(s:prototype)
  call instance.set_program()
  call instance.prompt()
  call instance.run_program()
endfunction
