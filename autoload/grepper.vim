" vim: tw=80

let s:options = {
      \ 'dispatch':  0,
      \ 'quickfix':  1,
      \ 'open':      0,
      \ 'switch':    0,
      \ 'jump':      1,
      \ 'cword':     0,
      \ 'next_tool': '<tab>',
      \ 'tools':     ['git', 'ag', 'sift', 'pt', 'ack', 'grep', 'findstr'],
      \ 'git':       { 'grepprg':    'git grep -nI',
      \                'grepformat': '%f:%l:%m',
      \                'escape':     '\$.*%#[]' },
      \ 'ag':        { 'grepprg':    'ag --vimgrep',
      \                'grepformat': '%f:%l:%c:%m,%f:%l:%m',
      \                'escape':     '\^$.*+?()[]' },
      \ 'sift':      { 'grepprg':    'sift -in --binary-skip $* .',
      \                'grepformat': '%f:%l:%m',
      \                'escape':     '\+*?^$#()[].' },
      \ 'pt':        { 'grepprg':    'pt --nogroup',
      \                'grepformat': '%f:%l:%m' },
      \ 'ack':       { 'grepprg':    'ack --noheading --column',
      \                'grepformat': '%f:%l:%c:%m',
      \                'escape':     '\^$.*+?()[]' },
      \ 'grep':      { 'grepprg':    'grep -Rn $* .',
      \                'grepformat': '%f:%l:%m',
      \                'escape':     '\$.*[]' },
      \ 'findstr':   { 'grepprg':    'findstr -rspnc:"$*" *',
      \                'grepformat': '%f:%l:%m' },
      \ }

" Escape test line:
" .. ad\\f 40+  $ # @ ! % ^ & &*()_{}4304\ '  "" ? `9$343 %  $ ^ adfadf [ ad )  [  (

if exists('g:grepper')
  for key in keys(g:grepper)
    if type(g:grepper[key]) == type({})
      if !has_key(s:options, key)
        let s:options[key] = {}
      endif
      call extend(s:options[key], g:grepper[key])
    else
      let s:options[key] = g:grepper[key]
    endif
  endfor
endif

call filter(s:options.tools, 'executable(v:val)')

let ack     = index(s:options.tools, 'ack')
let ackgrep = index(s:options.tools, 'ack-grep')

if (ack >= 0) && (ackgrep >= 0)
  call remove(s:options.tools, ackgrep)
endif

let s:cmdline = ''
let s:id      = 0
let s:slash   = exists('+shellslash') && !&shellslash ? '\' : '/'

let s:magic_string = '$$$mAgIc###'

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
  execute 'tabnext' self.tabpage
  execute self.window .'wincmd w'

  execute (s:option('quickfix') ? 'cgetfile' : 'lgetfile') self.tempfile
  call delete(self.tempfile)

  let s:id = 0
  call s:restore_settings()
  return s:finish_up()
endfunction
" }}}

" #complete_files() {{{1
function! grepper#complete_files(lead, line, _)
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
" }}}

" #parse_flags() {{{1
function! grepper#parse_flags(bang, args) abort
  let s:flags = {
        \ 'jump':   !a:bang,
        \ 'prompt': 1,
        \ 'query':  ''
        \ }
  let args = split(a:args, '\s\+')
  let len = len(args)
  let i = 0

  while i < len
    let flag = args[i]

    if     flag =~? '\v^-%(no)?dispatch$' | let s:flags.dispatch = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?quickfix$' | let s:flags.quickfix = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?open$'     | let s:flags.open     = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?switch$'   | let s:flags.switch   = flag !~? '^-no'
    elseif flag =~? '^-cword!\=$'
      let s:flags.cword = 1
      let s:flags.prompt = flag !~# '!$'
    elseif flag =~? '^-args$'
      let s:flags.args = join(args[(i+1):])
      break
    elseif flag =~? '^-query$'
      if i < len
        " Funny Vim bug: [i:] doesn't work. [(i):] and [i :] do.
        let s:flags.query = join(args[(i+1):])
        let s:flags.prompt = 0
        break
      else
        " No warning message here. This allows for..
        " nnoremap ... :Grepper! -tool ag -query<space>
        " ..thus you get nicer file completion.
        break
      endif
    elseif flag =~? '^-tool$'
      let i += 1
      if i < len
        let tool = args[i]
      else
        echomsg 'Missing argument for: -tool'
        break
      endif
      if index(s:options.tools, tool) >= 0
        let s:flags.tools =
              \ [tool] + filter(copy(s:options.tools), 'v:val != tool')
      else
        echomsg 'No such tool: '. tool
      endif
    else
      echomsg 'Ignore unknown flag: '. flag
    endif

    let i += 1
  endwhile

  return s:start()
endfunction

" s:process_flags() {{{1
function! s:process_flags()
  if get(s:flags, 'cword')
    let s:flags.query = s:escape_query(expand('<cword>'))
    if s:flags.prompt
      let s:flags.query = s:prompt(s:flags.query)
    endif
  else
    if s:flags.prompt
      let s:flags.query = s:prompt(s:flags.query)
    endif
    if empty(s:flags.query)
      let s:flags.query = s:escape_query(expand('<cword>'))
    endif
  endif
endfunction

" s:start() {{{1
function! s:start() abort
  if empty(s:options.tools)
    call s:error('No grep tool found!')
    return
  endif

  call s:process_flags()
  return s:run()
endfunction

" s:prompt() {{{1
function! s:prompt(query)
  let mapping = maparg(s:options.next_tool, 'c', '', 1)
  execute 'cnoremap' s:options.next_tool s:magic_string .'<cr>'
  echohl Question
  call inputsave()

  try
    let query = input(s:option('deftool').grepprg .'> ', a:query,
          \ 'customlist,grepper#complete_files')
  finally
    execute 'cunmap' s:options.next_tool
    call inputrestore()
    call s:restore_mapping(mapping)
    echohl NONE
  endtry

  if query =~# s:magic_string
    call histdel('input')
    let query = query[:-12]
    call s:tool_next()
    return s:prompt(s:tool_escape(a:query))
  endif

  return query
endfunction

" s:run() {{{1
function! s:run()
  let prog = s:option('deftool')

  if stridx(prog.grepprg, '$*') >= 0
    let [a, b] = split(prog.grepprg, '\V$*', 1)
    let s:cmdline = printf('%s%s%s', a, s:flags.query, b)
  else
    let s:cmdline = printf('%s %s', prog.grepprg, s:flags.query)
  endif

  call s:set_settings(prog)

  if has('nvim')
    if s:id
      silent! call jobstop(s:id)
    endif

    let cmd = ['sh', '-c', s:cmdline]

    let tempfile = fnameescape(tempname())
    if exists('*mkdir')
      silent! call mkdir(fnamemodify(tempfile, ':h'), 'p', 0600)
    endif
    let cmd[-1] .= ' >'. tempfile

    let s:id = jobstart(cmd, {
          \ 'tempfile':  tempfile,
          \ 'cmd':       s:cmdline,
          \ 'tabpage':   tabpagenr(),
          \ 'window':    winnr(),
          \ 'on_stderr': function('s:on_stderr'),
          \ 'on_exit':   function('s:on_exit') })
    return
  elseif s:option('dispatch')
    augroup grepper
      autocmd FileType qf call s:finish_up()
    augroup END
    try
      " The 'cat' is currently needed to strip these control sequences from
      " tmux output (http://stackoverflow.com/a/13608153):
      "   - CSI ? 1h + ESC =
      "   - CSI ? 1l + ESC >
      execute 'Make' s:flags.query '| cat'
    finally
      call s:restore_settings()
    endtry
  else
    try
      execute 'silent' (s:option('quickfix') ? 'grep!' : 'lgrep!') s:flags.query
    finally
      call s:restore_settings()
    endtry
    call s:finish_up()
  endif
endfunction

" s:option() {{{1
function! s:option(opt) abort
  if a:opt == 'deftool'
    if exists('s:flags') && has_key(s:flags, 'tools')
      return s:options[s:flags.tools[0]]
    else
      return s:options[s:options.tools[0]]
    endif
  else
    return has_key(s:flags, a:opt) ? s:flags[a:opt] : s:options[a:opt]
  endif
endfunction

" s:set_settings() {{{1
function! s:set_settings(prog) abort
  let s:settings = {}

  if !has('nvim') || !s:option('dispatch')
    let s:settings.t_ti = &t_ti
    let s:settings.t_te = &t_te
    set t_ti= t_te=
  endif

  let s:settings.grepprg = &grepprg
  let s:settings.makeprg = &makeprg
  let &grepprg = a:prog.grepprg
  let &makeprg = a:prog.grepprg

  if has_key(a:prog, 'grepformat')
    let s:settings.grepformat  = &grepformat
    let s:settings.errorformat = &errorformat
    let &grepformat  = a:prog.grepformat
    let &errorformat = a:prog.grepformat
  endif
endfunction

" s:restore_settings() {{{1
function! s:restore_settings() abort
    let &grepprg = s:settings.grepprg
    let &makeprg = s:settings.makeprg

    if has_key(s:settings, 'grepformat')
      let &grepformat  = s:settings.grepformat
      let &errorformat = s:settings.errorformat
    endif

    if has_key(s:settings, 't_ti')
      let &t_ti = s:settings.t_ti
      let &t_te = s:settings.t_te
    endif
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

" s:finish_up() {{{1
function! s:finish_up() abort
  augroup grepper
    autocmd!
  augroup END

  let qf = s:option('quickfix')
  let size = len(qf ? getqflist() : getloclist(0))

  if size == 0
    execute (qf ? 'cclose' : 'lclose')
    echo 'No matches found.'
  else
    if s:option('jump')
      execute (qf ? 'cfirst' : 'lfirst')
    endif

    if s:option('open')
      execute (qf ? 'copen' : 'lopen') (size > 10 ? 10 : size)
      let w:quickfix_title = s:cmdline
      if xor(s:option('switch'), !s:option('dispatch'))
        call feedkeys("\<c-w>p", 'n')
      else
        nnoremap <buffer> t :execute 'normal! 0'<cr>:tabedit <cr>
        nnoremap <buffer> s :execute 'normal! 0'<cr>:aboveleft split <cr>
      endif
    endif
  endif

  redraw!
  echo printf('Found %d matches.', size)
  silent doautocmd <nomodeline> User Grepper
endfunction

" s:tool_escape() {{{1
function! s:tool_escape(query)
  let tool = s:option('deftool')

  if exists('s:original_query')
    let query = has_key(tool, 'escape')
          \ ? escape(s:original_query, tool.escape)
          \ : s:original_query
    return shellescape(query)
  else
    return a:query
  endif
endfunction

" s:tool_next() {{{1
function! s:tool_next()
  if has_key(s:flags, 'tools')
    let s:flags.tools = s:flags.tools[1:-1] + [s:flags.tools[0]]
  else
    let s:options.tools = s:options.tools[1:-1] + [s:options.tools[0]]
  endif
endfunction

" s:escape_query() {{{1
function! s:escape_query(query)
  let s:original_query = a:query
  return s:tool_escape(s:original_query)
endfunction
" }}}

" #operator() {{{1
function! grepper#operator(type) abort
  let regsave = @@
  let selsave = &selection
  let &selection = 'inclusive'

  if a:type =~? 'v'
    silent execute "normal! gvy"
  elseif a:type == 'line'
    silent execute "normal! '[V']y"
  else
    silent execute "normal! `[v`]y"
  endif

  let &selection = selsave
  let s:flags = {
        \ 'prompt': 1,
        \ 'query': s:escape_query(@@)
        \ }
  let @@ = regsave

  return s:start()
endfunction
