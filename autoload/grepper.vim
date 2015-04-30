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

" s:callback_on_stderr() {{{1
function! s:callback_on_stderr(id, data)
  echomsg 'STDERR: '. join(a:data)
endfunction

" s:callback_on_exit() {{{1
function! s:callback_on_exit()
  " echon 'done!'
  execute 'silent buffer' s:grepper.window.bufnr
  silent 1delete
  setlocal nomodified
  if bufexists(expand('#'))
    silent buffer #
  endif
  echo 'Running '
  echohl Identifier
  echon s:grepper.option.program .' '. s:grepper.process.args
  echohl NONE
endfunction

" main data structure {{{1
let s:grepper = {
      \ 'option': {
      \   'program'  : '',
      \   'preview'  : 0,
      \   'height'   : 10,
      \   },
      \ 'window': {
      \   'bufnr'   : -1,
      \   },
      \ 'process': {
      \   'id'       : -1,
      \   'lines'    : 0,
      \   'args'     : '',
      \   'callbacks': {
      \     'on_stderr': function('s:callback_on_stderr'),
      \     'on_exit'  : function('s:callback_on_exit'),
      \     }
      \   }
      \ }
" grepper#start() {{{1
function! grepper#start()
  call s:prompt()
  " echomsg 'FOO: '. s:grepper.process.args
  if empty(s:grepper.process.args)
    if bufexists(s:grepper.window.bufnr)
      execute 'silent bwipeout!' s:grepper.window.bufnr
    endif
  else
    call s:set_program(s:grepper.process.args)
    call s:setup_window()
    call s:run_program()
  endif
endfunction

" s:prompt() {{{1
function! s:prompt()
  echohl Identifier
  call inputsave()
  let s:grepper.process.args = input('grepper> ')
  call inputrestore()
  echohl NONE
endfunction

" s:set_program() {{{1
function! s:set_program(args)
  if empty(s:grepper.option.program)
    if executable('git')
      let s:grepper.option.program = 'command git grep -i'
      let s:grepper.process.callbacks.on_stdout =
            \ function('s:callback_on_stdout_git')
    elseif executable('ag')
      let s:grepper.option.program = 'command ag --vimgrep'
      let s:grepper.process.callbacks.on_stdout =
            \ function('s:callback_on_stdout_ag')
    elseif executable('grep')
      let s:grepper.option.program = 'command grep -Ri'
    endif
  endif
  let s:grepper.process.args = a:args
endfunction

" s:setup_window() {{{1
function! s:setup_window()
  if s:grepper.window.bufnr == -1
    execute s:grepper.option.height .'new'
  else
    execute 'silent buffer' s:grepper.window.bufnr
    silent %delete
    return
  endif
  setlocal filetype=grepper nobuflisted buftype=nofile
  setlocal number norelativenumber
  let s:grepper.process.lines = 0
  let s:grepper.window.bufnr = bufnr('%')
  " TODO
  nnoremap <buffer> q :execute 'bwipeout!' s:grepper.window.bufnr<cr>
  augroup grepper
    autocmd BufWipeout <buffer> let s:grepper.window.bufnr = -1
  augroup END
endfunction

" s:run_program() {{{1
function! s:run_program()
  " echo 'Running '
  " echohl Identifier
  " echon s:grepper.option.program .' '. s:grepper.process.args
  " echohl NONE
  " echon ' ... '
  let id = jobstart(split(s:grepper.option.program) +
        \ [s:grepper.process.args], s:grepper.process.callbacks)
endfunction

