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
  silent! call jobstop(a:id)
  let self.errmsg = join(a:data)
endfunction

" s:on_exit() {{{1
function! s:on_exit() abort
  execute 'tabnext' self.tabpage
  execute self.window .'wincmd w'

  execute (self.flags.quickfix ? 'cgetfile' : 'lgetfile') self.tempfile
  call delete(self.tempfile)

  let s:id = 0
  call s:restore_settings()
  return s:finish_up(self.flags, self.errmsg)
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
  let flags = extend({ 'prompt': 1, 'query': ''}, s:options)
  let args = split(a:args, '\s\+')
  let len = len(args)
  let i = 0

  while i < len
    let flag = args[i]

    if     flag =~? '\v^-%(no)?dispatch$' | let flags.dispatch = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?quickfix$' | let flags.quickfix = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?open$'     | let flags.open     = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?switch$'   | let flags.switch   = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?jump$'     | let flags.jump     = flag !~? '^-no'
    elseif flag =~? '^-cword!\=$'
      let flags.cword = 1
      let flags.prompt = flag !~# '!$'
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
  " check for vim-dispatch
  if has('nvim') || !exists(':FocusDispatch')
    let a:flags.dispatch = 0
  endif
  " vim-dispatch always uses the quickfix window
  if a:flags.dispatch
    let a:flags.quickfix = 1
  endif

  if a:flags.cword
    let a:flags.query = s:escape_query(a:flags, expand('<cword>'))
    if a:flags.prompt
      call s:prompt(a:flags)
    endif
  else
    if a:flags.prompt
      call s:prompt(a:flags)
    endif
    echomsg 'Q: '. a:flags.query
    if empty(a:flags.query)
      let a:flags.query = s:escape_query(a:flags, expand('<cword>'))
    endif
  endif
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
    call histdel('input')
    call s:next_tool(a:flags)
    let a:flags.query = has_key(a:flags, 'query_orig')
          \ ? s:escape_query(a:flags, a:flags.query_orig)
          \ : a:flags.query[:-len(s:magic.next)-1]
    return s:prompt(a:flags)
  endif
endfunction

" s:build_cmdline() {{{1
function! s:build_cmdline(flags, grepprg) abort
  if stridx(a:grepprg, '$*') >= 0
    let [a, b] = split(a:grepprg, '\V$*', 1)
    return printf('%s%s%s', a, a:flags.query, b)
  else
    return printf('%s %s', a:grepprg, a:flags.query)
  endif
endfunction

" s:run() {{{1
function! s:run(flags)
  let prog = s:get_current_tool(a:flags)
  let s:cmdline = s:build_cmdline(a:flags, prog.grepprg)

  call s:store_settings(a:flags, prog)

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
          \ 'flags':     a:flags,
          \ 'tempfile':  tempfile,
          \ 'cmd':       s:cmdline,
          \ 'tabpage':   tabpagenr(),
          \ 'window':    winnr(),
          \ 'on_stderr': function('s:on_stderr'),
          \ 'on_exit':   function('s:on_exit'),
          \ 'errmsg':    '' })
    return
  elseif a:flags.dispatch
    " Just a hack since autocmds can't access local variables.
    let g:grepper_flags = deepcopy(a:flags)
    augroup grepper
      autocmd FileType qf call s:finish_up(g:grepper_flags)
    augroup END
    try
      let &makeprg = s:cmdline
      silent Make
    finally
      call s:restore_settings()
    endtry
  else
    try
      execute 'silent' (a:flags.quickfix ? 'grep!' : 'lgrep!') escape(a:flags.query, '#%')
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
function! s:store_settings(flags, prog) abort
  let s:settings = {}

  if !has('nvim') || !a:flags.dispatch
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
function! s:finish_up(flags, ...) abort
  augroup grepper
    autocmd!
  augroup END

  if exists('g:grepper_flags')
    unlet g:grepper_flags
  endif

  let qf = a:flags.quickfix
  let size = len(qf ? getqflist() : getloclist(0))

  if a:0 && !empty(a:1)
    call s:error(a:1)
  elseif size == 0
    execute (qf ? 'cclose' : 'lclose')
    echo 'No matches found.'
  else
    if a:flags.jump
      execute (qf ? 'cfirst' : 'lfirst')
      if a:flags.dispatch
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

    if a:flags.dispatch
      if a:flags.switch
        call feedkeys("\<c-w>p", 'n')
      endif
    else
      if !a:flags.open
        execute (qf ? 'cclose' : 'lclose')
      elseif !a:flags.switch
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

" s:escape_query() {{{1
function! s:escape_query(flags, query)
  let tool = s:get_current_tool(a:flags)
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
  let flags.prompt = 1
  let flags.query_orig = @@
  let flags.query = s:escape_query(flags, @@)
  let @@ = regsave

  return s:start(flags)
endfunction
