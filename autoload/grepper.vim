" s:callback_on_stdout_git() {{{1
function! s:callback_on_stdout_git(id, data)
  execute 'buffer' s:grepper.window.bufnr
  for line in a:data
    let tokens = matchlist(line, '\v^(.{-}):(.*)$')
    if empty(tokens)
      break
    endif
    let s:grepper.process.lines += 1
    call append(line('$'), printf('%s | %s', tokens[1], tokens[2]))
  endfor
  wincmd p
endfunction

" s:callback_on_stdout_ag() {{{1
function! s:callback_on_stdout_ag(id, data)
  execute 'buffer' s:grepper.window.bufnr
  for line in a:data
    let tokens = matchlist(line, '\v^(.{-}):(\d+):(\d+):(.*)$')
    if empty(tokens)
      break
    endif
    let s:grepper.process.lines += 1
    call append(line('$'), printf('%s | %s', tokens[1], tokens[4]))
  endfor
  wincmd p
endfunction
" }}}

" s:prototype {{{1
let s:prototype = {
      \ 'program': {
      \   'order': ['git', 'ag', 'grep'],
      \   'git' : 'git grep -ne',
      \   'ag'  : 'command ag --vimgrep',
      \   'grep': 'command grep -Ri',
      \   },
      \ 'process': {
      \   'cmd'      : '',
      \   'callbacks': {},
      \   },
      \ }

if exists('g:grepper')
  call extend(s:prototype, g:grepper)
endif

" s:prototype.process.callbacks.on_stderr() {{{1
function! s:prototype.process.callbacks.on_stderr(id, data)
  echomsg 'STDERR: '. join(a:data)
endfunction

" s:prototype.process.callbacks.on_exit() {{{1
function! s:prototype.process.callbacks.on_exit()
endfunction

" s:prototype.prompt() {{{1
function! s:prototype.prompt()
  echohl Identifier
  call inputsave()
  let input = input(self.process.cmd .'> ')
  call inputrestore()
  echohl NONE
  redraw!
  return self.process.cmd .' '. input
endfunction

" s:prototype.set_program() {{{1
function! s:prototype.set_program()
  for program in self.program.order
    if executable(program)
      let self.process.cmd = self.program[program]
      let self.process.callbacks.on_stdout =
            \ function('s:callback_on_stdout_'. program)
      return
    endif
  endfor
endfunction

" s:prototype.run_program() {{{1
function! s:prototype.run_program(cmd)
  " if has('nvim')
  "   let id = jobstart(split(a:cmd), self.process.callbacks)
  "   return
  " endif

  let old_grepprg = &grepprg
  let &grepprg = a:cmd
  try
    silent lgrep
    lopen
  finally
    let &grepprg = old_grepprg
  endtry
endfunction
" }}}

" grepper#start() {{{1
function! grepper#start()
  let instance = copy(s:prototype)
  call instance.set_program()
  call instance.run_program(instance.prompt())
endfunction
