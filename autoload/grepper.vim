let s:options = {
      \ 'quickfix':  1,
      \ 'open':      0,
      \ 'switch':    0,
      \ 'jump':      1,
      \ 'next_tool': '<tab>',
      \ 'tools':     ['git', 'ag', 'pt', 'ack', 'grep', 'findstr'],
      \ 'git':       { 'grepprg': 'git grep -n',              'grepformat': '%f:%l:%m'    },
      \ 'ag':        { 'grepprg': 'ag --vimgrep',             'grepformat': '%f:%l:%c:%m' },
      \ 'pt':        { 'grepprg': 'pt --nogroup',             'grepformat': '%f:%l:%m'    },
      \ 'ack':       { 'grepprg': 'ack --noheading --column', 'grepformat': '%f:%l:%c:%m' },
      \ 'grep':      { 'grepprg': 'grep -Rn $* .',            'grepformat': '%f:%l:%m'    },
      \ 'findstr':   { 'grepprg': 'findstr -rspnc:"$*" *',    'grepformat': '%f:%l:%m'    },
      \ }

if exists('g:grepper')
  call extend(s:options, g:grepper)
endif

call filter(s:options.tools, 'executable(v:val)')

let ack     = index(s:options.tools, 'ack')
let ackgrep = index(s:options.tools, 'ack-grep')

if (ack >= 0) && (ackgrep >= 0)
  call remove(s:options.tools, ackgrep)
endif

let s:id    = 0
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
  execute 'tabnext' self.tabpage
  execute self.window .'wincmd w'

  execute (s:get_option('quickfix') ? 'cgetfile' : 'lgetfile') self.tempfile
  call delete(self.tempfile)

  let s:id = 0
  call s:restore_settings()
  return s:finish_up(self.cmd)
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

" #parse_command() {{{1
function! grepper#parse_command(bang, ...) abort
  let s:flags = { 'jump': !a:bang }

  let i = 0
  while i < a:0
    let flag = a:000[i]

    if     flag =~? '\v^-%(no)?quickfix$' | let s:flags.quickfix = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?open$'     | let s:flags.open     = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?switch$'   | let s:flags.switch   = flag !~? '^-no'
    elseif flag =~? '^-search$'
      let i += 1
      if i < a:0
        " Funny Vim bug: [i:] doesn't work. [(i):] and [i :] do.
        return s:start(join(a:000[i :]), 1)
      else
        " No warning message here. This allows for..
        " nnoremap ... :Grepper! -tool ag -search<space>
        " ..thus you get nicer file completion.
        break
      endif
    elseif flag =~? '^-tool$'
      let i += 1
      if i < a:0
        let tool = a:000[i]
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
      echomsg "Don't understand: ". flag
    endif

    let i += 1
  endwhile

  return s:start('', 0)
endfunction

" s:start() {{{1
function! s:start(search, skip_prompt) abort
  if empty(s:options.tools)
    call s:error('No grep program found!')
    return
  endif

  let search = a:search
  let search = a:skip_prompt ? a:search : s:prompt(a:search)
  if empty(search)
    return
  endif

  return s:run_program(search)
endfunction

" s:prompt() {{{1
function! s:prompt(search)
  let mapping = maparg(s:options.next_tool, 'c', '', 1)
  execute 'cnoremap' s:options.next_tool '$$$mAgIc###<cr>'
  echohl Question
  call inputsave()

  try
    let search = input(s:get_option('deftool').grepprg .'> ', a:search,
          \ 'customlist,grepper#complete_files')
  finally
    execute 'cunmap' s:options.next_tool
    call inputrestore()
    call s:restore_mapping(mapping)
    echohl NONE
  endtry

  if search =~# '\V$$$mAgIc###\$'
    call histdel('input')
    if has_key(s:flags, 'tools')
      let s:flags.tools =
            \ s:flags.tools[1:-1] + [s:flags.tools[0]]
    else
      let s:options.tools =
            \ s:options.tools[1:-1] + [s:options.tools[0]]
    endif
    return s:prompt(search[:-12])
  endif

  return search
endfunction

" s:run_program() {{{1
function! s:run_program(search)
  let prog = s:get_option('deftool')

  if stridx(prog.grepprg, '$*') >= 0
    let [a, b] = split(prog.grepprg, '\V$*')
    let cmdline = printf('%s%s%s', a, a:search, b)
  else
    let cmdline = printf('%s %s', prog.grepprg, a:search)
  endif

  call s:set_settings(prog)

  if has('nvim')
    if s:id
      silent! call jobstop(s:id)
    endif

    let cmd = ['sh', '-c', cmdline]

    let tempfile = fnameescape(tempname())
    if exists('*mkdir')
      silent! call mkdir(fnamemodify(tempfile, ':h'), 'p', 0600)
    endif
    let cmd[-1] .= ' >'. tempfile

    let s:id = jobstart(cmd, {
          \ 'tempfile':  tempfile,
          \ 'cmd':       cmdline,
          \ 'tabpage':   tabpagenr(),
          \ 'window':    winnr(),
          \ 'on_stderr': function('s:on_stderr'),
          \ 'on_exit':   function('s:on_exit') })
    return
  endif

  try
    execute 'silent' (s:get_option('quickfix') ? 'grep!' : 'lgrep!')
          \ fnameescape(a:search)
  finally
    call s:restore_settings()
  endtry

  call s:finish_up(cmdline)
endfunction

" s:get_option() {{{1
function! s:get_option(opt) abort
  if a:opt == 'deftool'
    if has_key(s:flags, 'tools')
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
  let s:settings.t_ti = &t_ti
  let s:settings.t_te = &t_te
  set t_ti= t_te=

  let s:settings.grepprg = &grepprg
  let &grepprg = a:prog.grepprg

  if has_key(a:prog, 'format')
    let s:settings.grepformat = &grepformat
    let &grepformat = a:prog.grepformat
  endif
endfunction

" s:restore_settings() {{{1
function! s:restore_settings() abort
    let &grepprg = s:settings.grepprg

    if has_key(s:settings, 'grepformat')
      let &grepformat = s:settings.grepformat
    endif

    let &t_ti = s:settings.t_ti
    let &t_te = s:settings.t_te
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
function! s:finish_up(cmd) abort
  let qf = s:get_option('quickfix')
  let size = len(qf ? getqflist() : getloclist(0))

  if size == 0
    execute (qf ? 'cclose' : 'lclose')
    echomsg 'No matches found.'
  else
    if s:get_option('open')
      execute (size > 10 ? 10 : size) (qf ? 'copen' : 'lopen')
      let &l:statusline = a:cmd
      if !s:get_option('switch')
        wincmd p
      endif
    endif
    if s:get_option('jump')
      execute (qf ? 'cfirst' : 'lfirst')
    endif
    redraw!
    echo printf('Found %d matches.', size)
  endif

  silent! doautocmd <nomodeline> User Grepper
endfunction
" }}}

" #operator() {{{1
function! grepper#operator(type, ...) abort
  let selsave = &selection
  let regsave = @@
  let &selection = 'inclusive'

  " if a:0
  "   silent execute "normal! gvy"
  if a:type == 'line'
    silent execute "normal! '[V']y"
  else
    silent execute "normal! `[v`]y"
  endif

  let s:flags = {}
  call s:start(@@, 0)

  let &selection = selsave
  let @@ = regsave
endfunction
