" vim: tw=80

" Escaping test line:
" ..ad\\f40+$':-# @=,!;%^&&*()_{}/ /4304\'""?`9$343%$ ^adfadf[ad)[(

let s:options = {
      \ 'dispatch':  0,
      \ 'quickfix':  1,
      \ 'open':      1,
      \ 'switch':    1,
      \ 'jump':      0,
      \ 'cword':     0,
      \ 'next_tool': '<tab>',
      \ 'tools':     ['git', 'ag', 'sift', 'pt', 'ack', 'grep', 'findstr'],
      \ 'git':       { 'grepprg':    'git grep -nI',
      \                'grepformat': '%f:%l:%m',
      \                'escape':     '\$.*%#[]' },
      \ 'ag':        { 'grepprg':    'ag --vimgrep',
      \                'grepformat': '%f:%l:%c:%m,%f:%l:%m',
      \                'escape':     '\^$.*+?()[]%#' },
      \ 'sift':      { 'grepprg':    'sift -i -n --binary-skip $* .',
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
if index(s:options.tools, 'ag') != -1
      \ && !exists('g:grepper.ag.grepprg')
      \ && split(system('ag --version'))[2] =~ '^\v\d+\.%([01]|2[0-4])'
  let s:options.ag.grepprg = 'ag --column --nogroup --noheading'
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

let s:magic = {
      \ 'next': '$$$next###',
      \ 'esc':  '$$$esc###' }

" s:error() {{{1
function! s:error(msg)
  echohl ErrorMsg
  echomsg a:msg
  echohl NONE
endfunction
" }}}

" s:on_stderr() {{{1
function! s:on_stderr(id, data) abort
  silent! call jobstop(a:id)
  let self.errmsg = join(a:data)
endfunction

" s:on_exit() {{{1
function! s:on_exit() abort
  execute 'tabnext' self.tabpage
  execute self.window .'wincmd w'

  execute (s:option('quickfix') ? 'cgetfile' : 'lgetfile') self.tempfile
  call delete(self.tempfile)

  let s:id = 0
  call s:restore_settings()
  return s:finish_up(self.errmsg)
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
  let s:flags = { 'prompt': 1, 'query':  '' }
  let args = split(a:args, '\s\+')
  let len = len(args)
  let i = 0

  while i < len
    let flag = args[i]

    if     flag =~? '\v^-%(no)?dispatch$' | let s:flags.dispatch = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?quickfix$' | let s:flags.quickfix = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?open$'     | let s:flags.open     = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?switch$'   | let s:flags.switch   = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?jump$'     | let s:flags.jump     = flag !~? '^-no'
    elseif flag =~? '^-cword!\=$'
      let s:flags.cword = 1
      let s:flags.prompt = flag !~# '!$'
    elseif flag =~? '^-grepprg$'
      let i += 1
      if i < len
        if !exists('tool')
          let tool = s:options.tools[0]
        endif
        let s:flags.tools = [tool]
        let s:flags[tool] = copy(s:options[tool])
        let s:flags[tool].grepprg = join(args[i :])
      else
        echomsg 'Missing argument for: -grepprg'
      endif
      break
    elseif flag =~? '^-query$'
      let i += 1
      if i < len
        " Funny Vim bug: [i:] doesn't work. [(i):] and [i :] do.
        let s:flags.query = join(args[i :])
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
  " check for vim-dispatch
  if has('nvim') || !exists(':FocusDispatch')
    let s:flags.dispatch = 0
  endif
  " vim-dispatch always uses the quickfix window
  if s:option('dispatch')
    let s:flags.quickfix = 1
  endif

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

  silent! unlet s:original_query
endfunction

" s:start() {{{1
function! s:start() abort
  if empty(s:options.tools)
    call s:error('No grep tool found!')
    return
  endif

  call s:process_flags()

  if s:flags.query =~# s:magic.esc
    redraw!
    return
  endif

  return s:run()
endfunction

" s:prompt() {{{1
function! s:prompt(query)
  let mapping = maparg(s:options.next_tool, 'c', '', 1)
  execute 'cnoremap' s:options.next_tool s:magic.next .'<cr>'
  execute 'cnoremap <esc>' s:magic.esc .'<cr>'
  echohl Question
  call inputsave()

  try
    let query = input(s:option('deftool').grepprg .'> ', a:query,
          \ 'customlist,grepper#complete_files')
  finally
    execute 'cunmap' s:options.next_tool
    call inputrestore()
    cunmap <esc>
    call s:restore_mapping(mapping)
    echohl NONE
  endtry

  if query =~# s:magic.next
    call histdel('input')
    call s:tool_next()
    return s:prompt(exists('s:original_query')
          \ ? s:tool_escape(a:query)
          \ : query[:-len(s:magic.next)-1])
  endif

  return query
endfunction

" s:build_cmdline() {{{1
function! s:build_cmdline(grepprg) abort
  if stridx(a:grepprg, '$*') >= 0
    let [a, b] = split(a:grepprg, '\V$*', 1)
    return printf('%s%s%s', a, s:flags.query, b)
  else
    return printf('%s %s', a:grepprg, s:flags.query)
  endif
endfunction

" s:run() {{{1
function! s:run()
  let prog = s:option('deftool')

  let s:cmdline = s:build_cmdline(prog.grepprg)

  call s:set_settings(prog)

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
          \ 'tempfile':  tempfile,
          \ 'cmd':       s:cmdline,
          \ 'tabpage':   tabpagenr(),
          \ 'window':    winnr(),
          \ 'on_stderr': function('s:on_stderr'),
          \ 'on_exit':   function('s:on_exit'),
          \ 'errmsg':    '' })
    return
  elseif s:option('dispatch')
    augroup grepper
      autocmd FileType qf call s:finish_up()
    augroup END
    try
      let &makeprg = s:cmdline
      silent Make
    finally
      call s:restore_settings()
    endtry
  else
    try
      execute 'silent' (s:option('quickfix') ? 'grep!' : 'lgrep!') escape(s:flags.query, '#%')
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
      if has_key(s:flags, s:flags.tools[0])
        return s:flags[s:flags.tools[0]]
      else
        return s:options[s:flags.tools[0]]
      endif
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
function! s:finish_up(...) abort
  augroup grepper
    autocmd!
  augroup END

  let qf = s:option('quickfix')
  let size = len(qf ? getqflist() : getloclist(0))

  if a:0 && !empty(a:1)
    call s:error(a:1)
  elseif size == 0
    execute (qf ? 'cclose' : 'lclose')
    echo 'No matches found.'
  else
    if s:option('jump')
      execute (qf ? 'cfirst' : 'lfirst')
      if s:option('dispatch')
        doautocmd BufRead
      endif
    endif

    execute (qf ? 'botright copen' : 'lopen') (size > 10 ? 10 : size)
    let w:quickfix_title = s:cmdline

    nnoremap <silent><buffer> <cr> <cr>zv
    nnoremap <silent><buffer> o    <cr>zv
    nnoremap <silent><buffer> O    <cr>zv<c-w>p
    nnoremap <silent><buffer> s    :call <sid>open_entry('split',   1)<cr>
    nnoremap <silent><buffer> S    :call <sid>open_entry('split',   0)<cr>
    nnoremap <silent><buffer> v    :call <sid>open_entry('vsplit',  1)<cr>
    nnoremap <silent><buffer> V    :call <sid>open_entry('vsplit',  0)<cr>
    nnoremap <silent><buffer> t    <c-w>gFzv
    nmap     <silent><buffer> T    tgT

    if s:option('dispatch')
      if s:option('switch')
        call feedkeys("\<c-w>p", 'n')
      endif
    else
      if !s:option('open')
        execute (qf ? 'cclose' : 'lclose')
      elseif !s:option('switch')
        call feedkeys("\<c-w>p", 'n')
      endif
      if !has('nvim')
        redraw!
      endif
    endif

    echo printf('Found %d matches.', size)
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
      execute "normal! \<cr>"
      if bufexists('#')
        buffer #
        execute a:cmd '#'
      else
        execute "normal! ``"
        execute a:cmd
        execute "normal! ``"
      end
    endif
    normal! zv
  catch /E36/
    call s:error('E36: Not enough room')
  finally
    " Window numbers get reordered after creating new windows.
    if !a:jump
      for buf in filter(tabpagebuflist(), 'buflisted(v:val)')
        if getbufvar(buf, '&filetype') == 'qf'
          execute bufwinnr(buf) 'wincmd w'
          return
        endif
      endfor
    endif
    let &switchbuf = swb
  endtry
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
