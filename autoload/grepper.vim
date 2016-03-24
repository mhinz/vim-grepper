" vim: tw=80

" Escaping test line:
" ..ad\\f40+$':-# @=,!;%^&&*()_{}/ /4304\'""?`9$343%$ ^adfadf[ad)[(

let s:options = {
      \ 'quickfix':  1,
      \ 'open':      1,
      \ 'switch':    1,
      \ 'jump':      0,
      \ 'cword':     0,
      \ 'prompt':    1,
      \ 'highlight': 0,
      \ 'next_tool': '<tab>',
      \ 'tools':     ['ag', 'ack', 'grep', 'findstr', 'sift', 'pt', 'git'],
      \ 'git':       { 'grepprg':    'git grep -nI',
      \                'grepformat': '%f:%l:%m',
      \                'escape':     '\$.*%#[]' },
      \ 'ag':        { 'grepprg':    'ag --vimgrep',
      \                'grepformat': '%f:%l:%c:%m,%f:%l:%m',
      \                'escape':     '\^$.*+?()[]%#' },
      \ 'sift':      { 'grepprg':    'sift -n --binary-skip',
      \                'grepformat': '%f:%l:%m',
      \                'escape':     '\+*?^$%#()[]' },
      \ 'pt':        { 'grepprg':    'pt --nogroup',
      \                'grepformat': '%f:%l:%m' },
      \ 'ack':       { 'grepprg':    'ack --noheading --column',
      \                'grepformat': '%f:%l:%c:%m',
      \                'escape':     '\^$.*+?()[]%#' },
      \ 'grep':      { 'grepprg':    'grep -Rn $* .',
      \                'grepformat': '%f:%l:%m',
      \                'escape':     '\$.*[]%#' },
      \ 'findstr':   { 'grepprg':    'findstr -rspnc:"$*" *',
      \                'grepformat': '%f:%l:%m' },
      \ }

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

for tool in s:options.tools
  if !has_key(s:options, tool)
        \ || !has_key(s:options[tool], 'grepprg')
        \ || !executable(expand(matchstr(s:options[tool].grepprg, '^[^ ]*')))
    call remove(s:options.tools, index(s:options.tools, tool))
  endif
endfor

" Special case: ag (-vimgrep isn't available in versions < 0.25)
if index(s:options.tools, 'ag') >= 0
      \ && !exists('g:grepper.ag.grepprg')
      \ && split(system('ag --version'))[2] =~ '^\v\d+\.%([01]|2[0-4])'
  let s:options.ag.grepprg = 'ag --column --nogroup'
endif

" Special case: ack (different distros use different names for ack)
let ack     = index(s:options.tools, 'ack')
let ackgrep = index(s:options.tools, 'ack-grep')
if (ack >= 0) && (ackgrep >= 0)
  call remove(s:options.tools, ackgrep)
endif

let s:cmdline = ''
let s:id      = 0
let s:slash   = exists('+shellslash') && !&shellslash ? '\' : '/'

let s:magic = { 'next': '$$$next###', 'esc': '$$$esc###' }

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

  execute (self.flags.quickfix ? 'cgetfile' : 'lgetfile') self.tempfile
  call delete(self.tempfile)

  let s:id = 0
  call s:restore_settings()
  return s:finish_up(self.flags)
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
function! grepper#parse_flags(args) abort
  let flags = extend({ 'query': '', 'query_escaped': 0 }, s:options)
  let args = split(a:args, '\s\+')
  let len = len(args)
  let i = 0

  while i < len
    let flag = args[i]

    if     flag =~? '\v^-%(no)?quickfix$'  | let flags.quickfix  = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?open$'      | let flags.open      = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?switch$'    | let flags.switch    = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?jump$'      | let flags.jump      = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?prompt$'    | let flags.prompt    = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?highlight$' | let flags.highlight = flag !~? '^-no'
    elseif flag =~? '^-cword$'             | let flags.cword     = 1
    elseif flag =~? '^-grepprg$'
      let i += 1
      if i < len
        if !exists('tool')
          let tool = s:options.tools[0]
        endif
        let flags.tools = [tool]
        let flags[tool] = copy(s:options[tool])
        let flags[tool].grepprg = join(args[i :])
      else
        echomsg 'Missing argument for: -grepprg'
      endif
      break
    elseif flag =~? '^-query$'
      let i += 1
      if i < len
        " Funny Vim bug: [i:] doesn't work. [(i):] and [i :] do.
        let flags.query = join(args[i :])
        let flags.prompt = 0
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
        let flags.tools =
              \ [tool] + filter(copy(s:options.tools), 'v:val != tool')
      else
        echomsg 'No such tool: '. tool
      endif
    else
      echomsg 'Ignore unknown flag: '. flag
    endif

    let i += 1
  endwhile

  return s:start(flags)
endfunction

" s:process_flags() {{{1
function! s:process_flags(flags)
  if a:flags.cword
    let a:flags.query = s:escape_query(a:flags, expand('<cword>'))
  endif

  if a:flags.prompt
    call s:prompt(a:flags)
    if empty(a:flags.query)
      let a:flags.query = s:escape_query(a:flags, expand('<cword>'))
    elseif a:flags.query =~# s:magic.esc
      return
    endif
  endif

  if a:flags.highlight
    call s:highlight_query(a:flags)
  endif

  call histadd('input', a:flags.query)
endfunction

" s:highlight_query() {{{1
function! s:highlight_query(flags)
  " Change Vim's '\'' to ' so it can be understood by /.
  let vim_query = substitute(a:flags.query, "'\\\\''", "'", 'g')

  " Remove surrounding quotes that denote a string.
  let start = vim_query[0]
  let end = vim_query[-1:-1]
  if start == end && start =~ "\['\"]"
    let vim_query = vim_query[1:-2]
  endif

  if a:flags.query_escaped
    let vim_query = s:unescape_query(a:flags, vim_query)
    let vim_query = escape(vim_query, '\')
    let vim_query = '\V'. vim_query
  else
    " \bfoo\b -> \<foo\> Assume only one pair.
    let vim_query = substitute(vim_query, '\v\\b(.{-})\\b', '\\<\1\\>', '')
    " *? -> \{-}
    let vim_query = substitute(vim_query, '*\\\=?', '\\{-}', 'g')
    " +? -> \{-1,}
    let vim_query = substitute(vim_query, '\\\=+\\\=?', '\\{-1,}', 'g')
    let vim_query = escape(vim_query, '+')
  endif

  let @/ = vim_query
  call histadd('search', vim_query)
  call feedkeys(":set hls\<bar>echo\<cr>", 'n')
endfunction

" s:unescape_query() {{{1
function! s:unescape_query(flags, query)
  let tool = s:get_current_tool(a:flags)
  let q = a:query
  for c in reverse(split(tool.escape, '\zs'))
    let q = substitute(q, '\V\\'.c, c, 'g')
  endfor
  return q
endfunction

" s:start() {{{1
function! s:start(flags) abort
  if empty(s:options.tools)
    call s:error('No grep tool found!')
    return
  endif

  call s:process_flags(a:flags)

  if a:flags.query =~# s:magic.esc
    redraw!
    return
  endif

  return s:run(a:flags)
endfunction

" s:prompt() {{{1
function! s:prompt(flags)
  let tool = s:get_current_tool(a:flags)
  let mapping = maparg(s:options.next_tool, 'c', '', 1)
  execute 'cnoremap' s:options.next_tool s:magic.next .'<cr>'
  execute 'cnoremap <esc>' s:magic.esc .'<cr>'
  echohl Question
  call inputsave()

  try
    let a:flags.query = input(tool.grepprg .'> ', a:flags.query,
          \ 'customlist,grepper#complete_files')
  finally
    execute 'cunmap' s:options.next_tool
    call inputrestore()
    cunmap <esc>
    call s:restore_mapping(mapping)
    echohl NONE
  endtry

  if a:flags.query =~# s:magic.next
    call histdel('input', -1)
    call s:next_tool(a:flags)
    let a:flags.query = has_key(a:flags, 'query_orig')
          \ ? s:escape_query(a:flags, a:flags.query_orig)
          \ : a:flags.query[:-len(s:magic.next)-1]
    return s:prompt(a:flags)
  elseif a:flags.query =~# s:magic.esc
    call histdel('input', -1)
  endif
endfunction

" s:build_cmdline() {{{1
function! s:build_cmdline(flags) abort
  let grepprg = s:get_current_tool(a:flags).grepprg
  let grepprg = substitute(grepprg, '\V$.', bufname(''), '')

  if stridx(grepprg, '$+') >= 0
    let buffers = filter(map(filter(range(1, bufnr('$')), 'bufloaded(v:val)'),
          \ 'bufname(v:val)'), 'filereadable(v:val)')
    let grepprg = substitute(grepprg, '\V$+', join(buffers), '')
  endif

  if stridx(grepprg, '$*') >= 0
    let grepprg = substitute(grepprg, '\V$*', escape(a:flags.query, '\&'), 'g')
  else
    let grepprg .= ' ' . a:flags.query
  endif

  return grepprg
endfunction

" s:run() {{{1
function! s:run(flags)
  let s:cmdline = s:build_cmdline(a:flags)
  call s:store_settings(a:flags)

  if has('nvim')
    if s:id
      silent! call jobstop(s:id)
    endif

    let tempfile = fnameescape(tempname())
    try
      call mkdir(fnamemodify(tempfile, ':h'), 'p', 0600)
    catch /E739/
      call s:error(v:exeption)
      call s:restore_settings()
      return
    endtry

    let cmd = ['sh', '-c', printf('%s > %s', s:cmdline, tempfile)]

    let s:id = jobstart(cmd, {
          \ 'pty':       1,
          \ 'flags':     a:flags,
          \ 'tempfile':  tempfile,
          \ 'cmd':       s:cmdline,
          \ 'tabpage':   tabpagenr(),
          \ 'window':    winnr(),
          \ 'on_stderr': function('s:on_stderr'),
          \ 'on_exit':   function('s:on_exit')})
    return
  else
    try
      execute 'silent' (a:flags.quickfix ? 'grep!' : 'lgrep!')
      redraw!
    finally
      call s:restore_settings()
    endtry
    call s:finish_up(a:flags)
  endif
endfunction

" s:get_current_tool() {{{1
function! s:get_current_tool(flags) abort
  return a:flags[a:flags.tools[0]]
endfunction

" s:store_settings() {{{1
function! s:store_settings(flags) abort
  let s:settings = {}
  let prog = s:get_current_tool(a:flags)

  if !has('nvim')
    let s:settings.t_ti = &t_ti
    let s:settings.t_te = &t_te
    set t_ti= t_te=
  endif

  let s:settings.grepprg = &grepprg
  let s:settings.makeprg = &makeprg
  let &grepprg = s:cmdline
  let &makeprg = s:cmdline

  if has_key(prog, 'grepformat')
    let s:settings.grepformat  = &grepformat
    let s:settings.errorformat = &errorformat
    let &grepformat  = prog.grepformat
    let &errorformat = prog.grepformat
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
function! s:finish_up(flags) abort
  let qf = a:flags.quickfix
  let size = len(qf ? getqflist() : getloclist(0))

  if size == 0
    execute (qf ? 'cclose' : 'lclose')
    echo 'No matches found.'
    return
  endif

  if a:flags.jump
    execute 'silent' (qf ? 'cfirst' : 'lfirst')
  endif

  if a:flags.open
    execute (qf ? 'botright copen' : 'lopen') (size > 10 ? 10 : size)
    let w:quickfix_title = s:cmdline
    setlocal nowrap

    nnoremap <silent><buffer> <cr> <cr>zv
    nnoremap <silent><buffer> o    <cr>zv
    nnoremap <silent><buffer> O    <cr>zv<c-w>p
    nnoremap <silent><buffer> s    :call <sid>open_entry('split',  1)<cr>
    nnoremap <silent><buffer> S    :call <sid>open_entry('split',  0)<cr>
    nnoremap <silent><buffer> v    :call <sid>open_entry('vsplit', 1)<cr>
    nnoremap <silent><buffer> V    :call <sid>open_entry('vsplit', 0)<cr>
    nnoremap <silent><buffer> t    <c-w>gFzv
    nmap     <silent><buffer> T    tgT

    if !a:flags.switch
      call feedkeys("\<c-w>p", 'n')
    endif
  endif

  echo printf('Found %d matches.', size)
  if a:flags.open && a:flags.switch
    echohl Comment
    echon ' oO=open sS=split vV=vsplit tT=tab'
    echohl NONE
  endif

  silent doautocmd <nomodeline> User Grepper
endfunction

" s:open_entry() {{{1
function! s:open_entry(cmd, jump)
  let swb = &switchbuf
  let &switchbuf = ''
  try
    if winnr('$') == 1
      execute "normal! \<cr>"
    else
      wincmd p
      execute 'rightbelow' a:cmd
      let win = s:jump_to_qf_win()
      execute "normal! \<cr>"
    endif
    normal! zv
  catch /E36/
    call s:error('E36: Not enough room')
  finally
    " Window numbers get reordered after creating new windows.
    if !a:jump
      if exists('win') && win >= 0
        execute win 'wincmd w'
      else
        call s:jump_to_qf_win()
      endif
    endif
    let &switchbuf = swb
  endtry
endfunction

" s:jump_to_qf_win() {{{1
function! s:jump_to_qf_win() abort
  for buf in filter(tabpagebuflist(), 'buflisted(v:val)')
    if getbufvar(buf, '&filetype') == 'qf'
      let win = bufwinnr(buf)
      execute win 'wincmd w'
      return win
    endif
  endfor
  return 0
endfunction

" s:escape_query() {{{1
function! s:escape_query(flags, query)
  let tool = s:get_current_tool(a:flags)
  let a:flags.query_escaped = 1
  return shellescape(has_key(tool, 'escape')
        \ ? escape(a:query, tool.escape)
        \ : a:query)
endfunction

" s:next_tool() {{{1
function! s:next_tool(flags)
  let a:flags.tools = a:flags.tools[1:-1] + [a:flags.tools[0]]
endfunction

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
  let flags = deepcopy(s:options)
  let flags.query_orig = @@
  let flags.query_escaped = 0
  let flags.query = s:escape_query(flags, @@)
  let @@ = regsave

  return s:start(flags)
endfunction
