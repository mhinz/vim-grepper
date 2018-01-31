" Initialization {{{1

" Escaping test line:
" ..ad\\f40+$':-# @=,!;%^&&*()_{}/ /4304\'""?`9$343%$ ^adfadf[ad)[(

"
" Default values that get used for missing values in g:grepper.
"
let s:defaults = {
      \ 'quickfix':      1,
      \ 'open':          1,
      \ 'switch':        1,
      \ 'jump':          0,
      \ 'cword':         0,
      \ 'prompt':        1,
      \ 'simple_prompt': 0,
      \ 'prompt_quote':  0,
      \ 'highlight':     0,
      \ 'buffer':        0,
      \ 'buffers':       0,
      \ 'append':        0,
      \ 'side':          0,
      \ 'side_cmd':      'vnew',
      \ 'stop':          5000,
      \ 'dir':           'cwd',
      \ 'next_tool':     '<tab>',
      \ 'repo':          ['.git', '.hg', '.svn'],
      \ 'tools':         ['ag', 'ack', 'ack-grep', 'grep', 'findstr', 'rg', 'pt', 'sift', 'git'],
      \ 'git':           { 'grepprg':    'git grep -nI',
      \                    'grepformat': '%f:%l:%m',
      \                    'escape':     '\^$.*[]' },
      \ 'ag':            { 'grepprg':    'ag --vimgrep',
      \                    'grepformat': '%f:%l:%c:%m,%f:%l:%m',
      \                    'escape':     '\^$.*+?()[]{}|' },
      \ 'rg':            { 'grepprg':    'rg -H --no-heading --vimgrep',
      \                    'grepformat': '%f:%l:%c:%m',
      \                    'escape':     '\^$.*+?()[]{}|' },
      \ 'pt':            { 'grepprg':    'pt --nogroup',
      \                    'grepformat': '%f:%l:%m' },
      \ 'sift':          { 'grepprg':    'sift -n --column --binary-skip $* .',
      \                    'grepprgbuf': 'sift -n --column --binary-skip --filename -- $* $.',
      \                    'grepformat': '%f:%l:%c:%m',
      \                    'escape':     '\+*?^$%#()[]' },
      \ 'ack':           { 'grepprg':    'ack --noheading --column',
      \                    'grepformat': '%f:%l:%c:%m',
      \                    'escape':     '\^$.*+?()[]{}|' },
      \ 'ack-grep':      { 'grepprg':    'ack-grep --noheading --column',
      \                    'grepformat': '%f:%l:%c:%m',
      \                    'escape':     '\^$.*+?()[]{}|' },
      \ 'grep':          { 'grepprg':    'grep -RIn $* .',
      \                    'grepprgbuf': 'grep -HIn -- $* $.',
      \                    'grepformat': '%f:%l:%m',
      \                    'escape':     '\^$.*[]' },
      \ 'findstr':       { 'grepprg':    'findstr -rspnc:$* *',
      \                    'grepprgbuf': 'findstr -rpnc:$* $.',
      \                    'grepformat': '%f:%l:%m',
      \                    'wordanchors': ['\<', '\>'] }
      \ }

" Make it possible to configure the global and operator behaviours separately.
let s:defaults.operator = deepcopy(s:defaults)
let s:defaults.operator.prompt = 0

let s:has_doau_modeline = v:version > 703 || v:version == 703 && has('patch442')

function! s:merge_configs(config, defaults) abort
  let new = deepcopy(a:config)

  " Add all missing default options.
  call extend(new, a:defaults, 'keep')

  " Global options.
  for k in keys(a:config)
    if k == 'operator'
      continue
    endif

    " If only part of an option dict was set, add the missing default keys.
    if type(new[k]) == type({}) && has_key(a:defaults, k) && new[k] != a:defaults[k]
      call extend(new[k], a:defaults[k], 'keep')
    endif

    " Inherit operator option from global option unless it already exists or
    " has a default value where the global option has not.
    if !has_key(new.operator, k) || (has_key(a:defaults, k)
          \                          && new[k] != a:defaults[k]
          \                          && new.operator[k] == s:defaults.operator[k])
      let new.operator[k] = deepcopy(new[k])
    endif
  endfor

  " Operator options.
  if has_key(a:config, 'operator')
    for opt in keys(a:config.operator)
      " If only part of an operator option dict was set, inherit the missing
      " keys from the global option.
      if type(new.operator[opt]) == type({}) && new.operator[opt] != new[opt]
        call extend(new.operator[opt], new[opt], 'keep')
      endif
    endfor
  endif

  return new
endfunction

let g:grepper = exists('g:grepper')
      \ ? s:merge_configs(g:grepper, s:defaults)
      \ : deepcopy(s:defaults)

for s:tool in g:grepper.tools
  if !has_key(g:grepper, s:tool)
        \ || !has_key(g:grepper[s:tool], 'grepprg')
        \ || !executable(expand(matchstr(g:grepper[s:tool].grepprg, '^[^ ]*')))
    call remove(g:grepper.tools, index(g:grepper.tools, s:tool))
  endif
endfor

"
" Special case: ag (-vimgrep isn't available in versions < 0.25)
"
if index(g:grepper.tools, 'ag') >= 0
      \ && !exists('g:grepper.ag.grepprg')
      \ && split(system('ag --version'))[2] =~ '^\v\d+\.%([01]|2[0-4])'
  let g:grepper.ag.grepprg = 'ag --column --nogroup'
endif

"
" Special case: ack (different distros use different names for ack)
" Prefer ack-grep since its presence likely means ack is a different tool.
"
let s:ack     = index(g:grepper.tools, 'ack')
let s:ackgrep = index(g:grepper.tools, 'ack-grep')
if (s:ack >= 0) && (s:ackgrep >= 0)
  call remove(g:grepper.tools, s:ack)
endif

let s:cmdline = ''
let s:slash   = exists('+shellslash') && !&shellslash ? '\' : '/'
let s:magic   = { 'next': '$$$next###', 'cr': '$$$cr###' }

" Job handlers {{{1
" s:on_stdout_nvim() {{{2
function! s:on_stdout_nvim(_job_id, data, _event) dict abort
  if !exists('s:id')
    return
  endif

  let orig_dir = s:chdir_push(self.work_dir)

  try
    if empty(a:data[-1])
      " Second-last item is the last complete line in a:data.
      noautocmd execute self.addexpr 'self.stdoutbuf + a:data[:-2]'
      let self.stdoutbuf = []
    else
      if empty(self.stdoutbuf)
        " Last item in a:data is an incomplete line. Put into buffer.
        let self.stdoutbuf = [remove(a:data, -1)]
        noautocmd execute self.addexpr 'a:data'
      else
        " Last item in a:data is an incomplete line. Append to buffer.
        let self.stdoutbuf = self.stdoutbuf[:-2]
              \ + [self.stdoutbuf[-1] . get(a:data, 0, '')]
              \ + a:data[1:]
      endif
    endif
    if self.flags.stop > 0
      let nmatches = len(self.flags.quickfix ? getqflist() : getloclist(0))
      if nmatches >= self.flags.stop || len(self.stdoutbuf) > self.flags.stop
        " Add the remaining data
        let n_rem_lines = self.flags.stop - nmatches - 1
        if n_rem_lines > 0
          noautocmd execute self.addexpr 'self.stdoutbuf[:n_rem_lines]'
        endif

        call jobstop(s:id)
        unlet s:id
      endif
    endif
  finally
    call s:chdir_pop(orig_dir)
  endtry
endfunction

" s:on_stdout_vim() {{{2
function! s:on_stdout_vim(_job_id, data) dict abort
  if !exists('s:id')
    return
  endif

  let orig_dir = s:chdir_push(self.work_dir)

  try
    noautocmd execute self.addexpr 'a:data'
    if self.flags.stop > 0
          \ && len(self.flags.quickfix ? getqflist() : getloclist(0)) >= self.flags.stop
      call job_stop(s:id)
      unlet s:id
    endif
  finally
    call s:chdir_pop(orig_dir)
  endtry
endfunction

" s:on_exit() {{{2
function! s:on_exit(...) dict abort
  execute 'tabnext' self.tabpage
  execute self.window .'wincmd w'
  silent! unlet s:id
  return s:finish_up(self.flags)
endfunction

" Completion {{{1
" grepper#complete() {{{2
function! grepper#complete(lead, line, _pos) abort
  if a:lead =~ '^-'
    let flags = ['-append', '-buffer', '-buffers', '-cword', '-dir', '-grepprg',
          \ '-highlight', '-jump', '-open', '-prompt', '-query', '-quickfix',
          \ '-side', '-stop', '-switch', '-tool', '-noappend', '-nohighlight',
          \ '-nojump', '-noopen', '-noprompt', '-noquickfix', '-noswitch']
    return filter(map(flags, 'v:val." "'), 'v:val[:strlen(a:lead)-1] ==# a:lead')
  elseif a:line =~# '-dir \w*$'
    return filter(map(['cwd', 'file', 'filecwd', 'repo'], 'v:val." "'),
          \ 'empty(a:lead) || v:val[:strlen(a:lead)-1] ==# a:lead')
  elseif a:line =~# '-stop $'
    return ['5000']
  elseif a:line =~# '-tool \w*$'
    return filter(map(sort(copy(g:grepper.tools)), 'v:val." "'),
          \ 'empty(a:lead) || v:val[:strlen(a:lead)-1] ==# a:lead')
  else
    return grepper#complete_files(a:lead, 0, 0)
  endif
endfunction

" grepper#complete_files() {{{2
function! grepper#complete_files(lead, _line, _pos)
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

" s:extract_path() {{{2
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

" Statusline {{{1
" #statusline() {{{2
function! grepper#statusline() abort
  return s:cmdline
endfunction

" Helpers {{{1
" s:error() {{{2
function! s:error(msg)
  redraw
  echohl ErrorMsg
  echomsg a:msg
  echohl NONE
endfunction

" s:lstrip() {{{2
function! s:lstrip(string) abort
  return substitute(a:string, '^\s\+', '', '')
endfunction

" s:split_one() {{{2
function! s:split_one(string) abort
  let stripped = s:lstrip(a:string)
  let first_word = substitute(stripped, '\v^(\S+).*', '\1', '')
  let rest = substitute(stripped, '\v^\S+\s*(.*)', '\1', '')
  return [first_word, rest]
endfunction

" s:next_tool() {{{2
function! s:next_tool(flags)
  let a:flags.tools = a:flags.tools[1:-1] + [a:flags.tools[0]]
endfunction

" s:get_current_tool() {{{2
function! s:get_current_tool(flags) abort
  return a:flags[a:flags.tools[0]]
endfunction

" s:get_current_tool_name() {{{2
function! s:get_current_tool_name(flags) abort
  return a:flags.tools[0]
endfunction

" s:get_grepprg() {{{2
function! s:get_grepprg(flags) abort
  let tool = s:get_current_tool(a:flags)
  if a:flags.buffers
    return has_key(tool, 'grepprgbuf')
          \ ? substitute(tool.grepprgbuf, '\V$.', '$+', '')
          \ : tool.grepprg .' -- $* $+'
  elseif a:flags.buffer
    return has_key(tool, 'grepprgbuf')
          \ ? tool.grepprgbuf
          \ : tool.grepprg .' -- $* $.'
  endif
  return tool.grepprg
endfunction

" s:store_errorformat() {{{2
function! s:store_errorformat(flags) abort
  let prog = s:get_current_tool(a:flags)
  let s:errorformat = &errorformat
  let &errorformat = has_key(prog, 'grepformat') ? prog.grepformat : &errorformat
endfunction

" s:restore_errorformat() {{{2
function! s:restore_errorformat() abort
  let &errorformat = s:errorformat
endfunction

" s:restore_mapping() {{{2
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

" s:escape_query() {{{2
function! s:escape_query(flags, query)
  let tool = s:get_current_tool(a:flags)
  let a:flags.query_escaped = 1
  return shellescape(has_key(tool, 'escape')
        \ ? escape(a:query, tool.escape)
        \ : a:query)
endfunction

" s:unescape_query() {{{2
function! s:unescape_query(flags, query)
  let tool = s:get_current_tool(a:flags)
  let q = a:query
  if has_key(tool, 'escape')
    for c in reverse(split(tool.escape, '\zs'))
      let q = substitute(q, '\V\\'.c, c, 'g')
    endfor
  endif
  return q
endfunction

" s:escape_cword() {{{2
function! s:escape_cword(flags, cword)
  let tool = s:get_current_tool(a:flags)
  let escaped_cword = has_key(tool, 'escape')
        \ ? escape(a:cword, tool.escape)
        \ : a:cword
  let wordanchors = has_key(tool, 'wordanchors')
        \ ? tool.wordanchors
        \ : ['\b', '\b']
  if a:cword =~# '^\k'
    let escaped_cword = wordanchors[0] . escaped_cword
  endif
  if a:cword =~# '\k$'
    let escaped_cword = escaped_cword . wordanchors[1]
  endif
  let a:flags.query_orig = a:cword
  let a:flags.query_escaped = 1
  return shellescape(escaped_cword)
endfunction

" s:compute_working_directory() {{{2
function! s:compute_working_directory(flags) abort
  for dir in split(a:flags.dir, ',')
    if dir == 'repo'
      if s:get_current_tool_name(a:flags) == 'git'
        let dir = system(printf('git -C %s rev-parse --show-toplevel',
              \ expand('%:p:h')))
        if !v:shell_error
          return dir
        endif
      endif
      for repo in g:grepper.repo
        let repopath = finddir(repo, '.;')
        if empty(repopath)
          let repopath = findfile(repo, '.;')
        endif
        if !empty(repopath)
          let repopath = fnamemodify(repopath, ':h')
          return fnameescape(repopath)
        endif
      endfor
    elseif dir == 'filecwd'
      let cwd = getcwd()
      let bufdir = expand('%:p:h')
      if stridx(bufdir, cwd) != 0
        return fnameescape(bufdir)
      endif
    elseif dir == 'file'
      let bufdir = expand('%:p:h')
      return fnameescape(bufdir)
    endif
  endfor
  return ''
endfunction

" s:chdir_push() {{{2
function! s:chdir_push(work_dir)
  if !empty(a:work_dir)
    let cwd = getcwd()
    execute 'lcd' a:work_dir
    return cwd
  endif
  return ''
endfunction

" s:chdir_pop() {{{2
function! s:chdir_pop(buf_dir)
  if !empty(a:buf_dir)
    execute 'lcd' fnameescape(a:buf_dir)
  endif
endfunction

" s:get_config() {{{2
function! s:get_config() abort
  let g:grepper = exists('g:grepper')
        \ ? s:merge_configs(g:grepper, s:defaults)
        \ : deepcopy(s:defaults)
  let flags = deepcopy(g:grepper)
  if exists('b:grepper')
    let flags = s:merge_configs(b:grepper, g:grepper)
  endif
  return flags
endfunction
" }}}1

" s:parse_flags() {{{1
function! s:parse_flags(args) abort
  let flags = s:get_config()
  let flags.query = ''
  let flags.query_escaped = 0
  let [flag, args] = s:split_one(a:args)

  while !empty(flag)
    if     flag =~? '\v^-%(no)?(quickfix|qf)$' | let flags.quickfix  = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?open$'          | let flags.open      = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?switch$'        | let flags.switch    = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?jump$'          | let flags.jump      = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?prompt$'        | let flags.prompt    = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?highlight$'     | let flags.highlight = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?buffer$'        | let flags.buffer    = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?buffers$'       | let flags.buffers   = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?append$'        | let flags.append    = flag !~? '^-no'
    elseif flag =~? '^-cword$'                 | let flags.cword     = 1
    elseif flag =~? '^-side$'                  | let flags.side      = 1
    elseif flag =~? '^-stop$'
      if empty(args) || args[0] =~ '^-'
        let flags.stop = -1
      else
        let [numstring, args] = s:split_one(args)
        let flags.stop = str2nr(numstring)
      endif
    elseif flag =~? '^-dir$'
      let [dir, args] = s:split_one(args)
      if empty(dir)
        call s:error('Missing argument for: -dir')
      else
        let flags.dir = dir
      endif
    elseif flag =~? '^-grepprg$'
      if empty(args)
        call s:error('Missing argument for: -grepprg')
      else
        if !exists('tool')
          let tool = g:grepper.tools[0]
        endif
        let flags.tools = [tool]
        let flags[tool] = copy(g:grepper[tool])
        let flags[tool].grepprg = args
      endif
      break
    elseif flag =~? '^-query$'
      if empty(args)
        " No warning message here. This allows for..
        " nnoremap ... :Grepper! -tool ag -query<space>
        " ..thus you get nicer file completion.
      else
        let flags.query = args
        let flags.prompt = 0
      endif
      break
    elseif flag =~? '^-tool$'
      let [tool, args] = s:split_one(args)
      if tool == ''
        call s:error('Missing argument for: -tool')
        break
      endif
      if index(g:grepper.tools, tool) >= 0
        let flags.tools =
              \ [tool] + filter(copy(g:grepper.tools), 'v:val != tool')
      else
        call s:error('No such tool: '. tool)
      endif
    else
      call s:error('Ignore unknown flag: '. flag)
    endif

    let [flag, args] = s:split_one(args)
  endwhile

  return s:start(flags)
endfunction

" s:process_flags() {{{1
function! s:process_flags(flags)
  if a:flags.stop == -1
    if exists('s:id')
      if has('nvim')
        call jobstop(s:id)
      else
        call job_stop(s:id)
      endif
      unlet s:id
    endif
    return 1
  endif

  if a:flags.buffer
    let [shellslash, &shellslash] = [&shellslash, 1]
    let a:flags.buflist = [fnamemodify(bufname(''), ':p')]
    let &shellslash = shellslash
    if !filereadable(a:flags.buflist[0])
      call s:error('This buffer is not backed by a file!')
      return 1
    endif
  endif

  if a:flags.buffers
    let [shellslash, &shellslash] = [&shellslash, 1]
    let a:flags.buflist = filter(map(filter(range(1, bufnr('$')),
          \ 'bufloaded(v:val)'), 'fnamemodify(bufname(v:val), ":p")'), 'filereadable(v:val)')
    let &shellslash = shellslash
    if empty(a:flags.buflist)
      call s:error('No buffer is backed by a file!')
      return 1
    endif
  endif

  if a:flags.cword
    let a:flags.query = s:escape_cword(a:flags, expand('<cword>'))
  endif

  if a:flags.prompt
    call s:prompt(a:flags)
    " Empty query string indicates that prompt was canceled
    if empty(a:flags.query)
      return
    endif
    " Remove marker indicating that prompt was accepted
    let a:flags.query = substitute(a:flags.query, '\V\C'.s:magic.cr .'\$', '', '')
    if empty(a:flags.query)
      let a:flags.query = s:escape_cword(a:flags, expand('<cword>'))
    elseif a:flags.prompt_quote == 1
      let a:flags.query = shellescape(a:flags.query)
    endif
  endif

  if a:flags.side
    let a:flags.highlight = 1
    let a:flags.open      = 0
  endif

  if a:flags.highlight
    call s:highlight_query(a:flags)
  endif

  call histadd('input', a:flags.query)

  return 0
endfunction

" s:start() {{{1
function! s:start(flags) abort
  if empty(g:grepper.tools)
    call s:error('No grep tool found!')
    return
  endif

  if s:process_flags(a:flags)
    return
  endif

  if a:flags.prompt && empty(a:flags.query)
    redraw!
    return
  endif

  return s:run(a:flags)
endfunction

" s:prompt() {{{1
function! s:prompt(flags)
  let prompt_text = a:flags.simple_prompt
        \ ? s:get_current_tool_name(a:flags)
        \ : s:get_grepprg(a:flags)

  let mapping = maparg(g:grepper.next_tool, 'c', '', 1)
  execute 'cnoremap' g:grepper.next_tool s:magic.next .'<cr>'
  execute 'cnoremap <cr> <end>'. s:magic.cr .'<cr>'

  " Set low timeout for key codes, so <esc> would cancel prompt faster
  let ttimeoutsave = &ttimeout
  let ttimeoutlensave = &ttimeoutlen
  let &ttimeout = 1
  let &ttimeoutlen = 100

  if a:flags.prompt_quote == 2 && !has_key(a:flags, 'query_orig')
    let a:flags.query = "'". a:flags.query ."'\<left>"
  elseif a:flags.prompt_quote == 3 && !has_key(a:flags, 'query_orig')
    let a:flags.query = '"'. a:flags.query ."\"\<left>"
  else
    let a:flags.query = a:flags.query
  endif

  echohl Question
  call inputsave()

  try
    let a:flags.query = input(prompt_text .'> ', a:flags.query,
          \ 'customlist,grepper#complete_files')
  finally
    redraw!
    execute 'cunmap' g:grepper.next_tool
    cunmap <cr>
    call s:restore_mapping(mapping)

    " Restore original timeout settings for key codes
    let &ttimeout = ttimeoutsave
    let &ttimeoutlen = ttimeoutlensave

    echohl NONE
    call inputrestore()
  endtry

  if !empty(a:flags.query)
    " Always delete entered line from the history because it contains magic
    " sequence. Real query will be added to the history later.
    call histdel('input', -1)
  endif

  if a:flags.query =~# s:magic.next
    call s:next_tool(a:flags)
    if a:flags.cword
      let a:flags.query = s:escape_cword(a:flags, a:flags.query_orig)
    else
      let is_findstr = s:get_current_tool_name(a:flags) == 'findstr'
      if has_key(a:flags, 'query_orig')
        let a:flags.query = (is_findstr ? '' : '-- '). s:escape_query(a:flags, a:flags.query_orig)
      else
        if a:flags.prompt_quote >= 2
          let a:flags.query = a:flags.query[1:-len(s:magic.next)-2]
        else
          let a:flags.query = a:flags.query[:-len(s:magic.next)-1]
        endif
      endif
    endif
    return s:prompt(a:flags)
  endif
endfunction

" s:build_cmdline() {{{1
function! s:build_cmdline(flags) abort
  let grepprg = s:get_grepprg(a:flags)

  if has_key(a:flags, 'buflist')
    let [shellslash, &shellslash] = [&shellslash, 1]
    call map(a:flags.buflist, 'shellescape(fnamemodify(v:val, ":."))')
    let &shellslash = shellslash
  endif

  if stridx(grepprg, '$.') >= 0
    let grepprg = substitute(grepprg, '\V$.', a:flags.buflist[0], '')
  endif
  if stridx(grepprg, '$+') >= 0
    let grepprg = substitute(grepprg, '\V$+', join(a:flags.buflist), '')
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
  if a:flags.quickfix
    call setqflist([])
  else
    call setloclist(0, [])
  endif

  let work_dir  = s:compute_working_directory(a:flags)
  let orig_dir  = s:chdir_push(work_dir)
  let s:cmdline = s:build_cmdline(a:flags)

  " 'cmd' and 'options' are only used for async execution.
  if has('win32') && &shell =~# 'powershell'
    " Windows powershell has better quote handling.
    let cmd = s:cmdline
  elseif has('win32') && &shell =~# 'cmd'
    " cmd.exe handles single quotes as part of the query. To avoid this
    " behaviour, we run the query via powershell.exe from within cmd.exe:
    " https://stackoverflow.com/questions/94382/vim-with-powershell
    let cmd = 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned '. s:cmdline
  else
    let cmd = ['sh', '-c', s:cmdline]
  endif

  let options = {
        \ 'cmd':       s:cmdline,
        \ 'work_dir':  work_dir,
        \ 'flags':     a:flags,
        \ 'addexpr':   a:flags.quickfix ? 'caddexpr' : 'laddexpr',
        \ 'window':    winnr(),
        \ 'tabpage':   tabpagenr(),
        \ 'stdoutbuf': [],
        \ }

  call s:store_errorformat(a:flags)

  if &verbose
    echomsg 'grepper: running' string(cmd)
  endif

  if has('nvim')
    if exists('s:id')
      silent! call jobstop(s:id)
    endif
    try
      let s:id = jobstart(cmd, extend(options, {
            \ 'on_stdout': function('s:on_stdout_nvim'),
            \ 'on_stderr': function('s:on_stdout_nvim'),
            \ 'stdout_buffered': 1,
            \ 'stderr_buffered': 1,
            \ 'on_exit':   function('s:on_exit'),
            \ }))
    finally
      call s:chdir_pop(orig_dir)
    endtry
  elseif !get(w:, 'testing') && has('patch-7.4.1967')
    if exists('s:id')
      silent! call job_stop(s:id)
    endif

    try
      let s:id = job_start(cmd, {
            \ 'in_io':    'null',
            \ 'err_io':   'out',
            \ 'out_cb':   function('s:on_stdout_vim', options),
            \ 'close_cb': function('s:on_exit', options),
            \ })
    finally
      call s:chdir_pop(orig_dir)
    endtry
  else
    try
      execute 'silent' (a:flags.quickfix ? 'cgetexpr' : 'lgetexpr') 'system(s:cmdline)'
    finally
      call s:chdir_pop(orig_dir)
    endtry
    call s:finish_up(a:flags)
  endif
endfunction

" s:finish_up() {{{1
function! s:finish_up(flags)
  let qf = a:flags.quickfix
  let list = qf ? getqflist() : getloclist(0)
  let size = len(list)

  let cmdline = s:cmdline
  let s:cmdline = ''

  call s:restore_errorformat()

  try
    let title = has('nvim') ? cmdline : {'title': cmdline}
    if qf
      call setqflist(list, a:flags.append ? 'a' : 'r', title)
    else
      call setloclist(0, list, a:flags.append ? 'a' : 'r', title)
    endif
  catch /E118/
  endtry

  if size == 0
    execute (qf ? 'cclose' : 'lclose')
    redraw
    echo 'No matches found.'
    return
  endif

  if a:flags.jump
    execute (qf ? 'cfirst' : 'lfirst')
  endif

  " Also open if the list contains any invalid entry.
  if a:flags.open || !empty(filter(list, 'v:val.valid == 0'))
    execute (qf ? 'botright copen' : 'lopen') (size > 10 ? 10 : size)
    let w:quickfix_title = cmdline
    setlocal nowrap

    if !a:flags.switch
      call feedkeys("\<c-w>p", 'n')
    endif
  endif

  redraw
  echo printf('Found %d matches.', size)

  if a:flags.side
    call s:side(a:flags)
  endif

  if exists('#User#Grepper')
    execute 'doautocmd' (s:has_doau_modeline ? '<nomodeline>' : '') 'User Grepper'
  endif
endfunction

" }}}1

" -highlight {{{1
" s:highlight_query() {{{2
function! s:highlight_query(flags)
  let query = has_key(a:flags, 'query_orig') ? a:flags.query_orig : a:flags.query

  " Change Vim's '\'' to ' so it can be understood by /.
  let vim_query = substitute(query, "'\\\\''", "'", 'g')

  " Remove surrounding quotes that denote a string.
  let start = vim_query[0]
  let end = vim_query[-1:-1]
  if start == end && start =~ "\['\"]"
    let vim_query = vim_query[1:-2]
  endif

  if a:flags.query_escaped
    let vim_query = s:unescape_query(a:flags, vim_query)
    let vim_query = escape(vim_query, '\')
    if a:flags.cword
      if a:flags.query_orig =~# '^\k'
        let vim_query = '\<' . vim_query
      endif
      if a:flags.query_orig =~# '\k$'
        let vim_query = vim_query . '\>'
      endif
    endif
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

" -side {{{1
let s:filename_regexp = '\v^%(\>\>\>|\]\]\]) ([[:alnum:][:blank:]\/\-_.~]+):(\d+)'

" s:side() {{{2
function! s:side(flags) abort
  call s:side_create_window(a:flags)
  call s:side_buffer_settings()
endfunction

" s:side_create_window() {{{2
function! s:side_create_window(flags) abort
  " Contexts are lists of a fixed format:
  "
  "   [0] = line number of the match
  "   [1] = start of context
  "   [2] = end of context
  let regions = {}
  let list = a:flags.quickfix ? getqflist() : getloclist(0)

  " process quickfix entries
  for entry in list
    let bufname = bufname(entry.bufnr)
    if has_key(regions, bufname)
      if (regions[bufname][-1][2] + 2) > entry.lnum
        " merge entries that are close to each other into the same context
        let regions[bufname][-1][2] = entry.lnum + 2
      else
        " new context in same file
        let start = (entry.lnum < 4) ? 0 : (entry.lnum - 4)
        let regions[bufname] += [[entry.lnum, start, entry.lnum + 2]]
      endif
    else
      " new context in new file
      let start = (entry.lnum < 4) ? 0 : (entry.lnum - 4)
      let regions[bufname] = [[entry.lnum, start, entry.lnum + 2]]
    end
  endfor

  execute a:flags.side_cmd

  " write contexts to buffer
  for filename in sort(keys(regions))
    let contexts = regions[filename]
    let file = readfile(expand(filename))

    let context = contexts[0]
    call append('$', '>>> '. filename .':'. context[0])
    call append('$', file[context[1]:context[2]])

    for context in contexts[1:]
      call append('$', ']]] '. filename .':'. context[0])
      call append('$', file[context[1]:context[2]])
    endfor

    call append('$', '')
  endfor

  silent 1delete _

  let nummatches = len(getqflist())
  let numfiles = len(uniq(map(getqflist(), 'bufname(v:val.bufnr)')))
  let &l:statusline = printf(' Found %d matches in %d files.', nummatches, numfiles)
endfunction

" s:side_buffer_settings() {{{2
function! s:side_buffer_settings() abort
  nnoremap <silent><buffer> q :bdelete<cr>

  nnoremap <silent><plug>(grepper-side-context-jump) :<c-u>call <sid>context_jump(1)
  nnoremap <silent><plug>(grepper-side-context-open) :<c-u>call <sid>context_jump(0)
  nnoremap <silent><plug>(grepper-side-context-next) :<c-u>call <sid>context_next()
  nnoremap <silent><plug>(grepper-side-context-prev) :<c-u>call <sid>context_previous()

  nmap <buffer> <cr> <plug>(grepper-side-context-jump)<cr>
  nmap <buffer> o    <plug>(grepper-side-context-open)<cr>
  nmap <buffer> }    <plug>(grepper-side-context-next)<cr>
  nmap <buffer> {    <plug>(grepper-side-context-prev)<cr>

  setlocal buftype=nofile bufhidden=wipe nonumber norelativenumber foldcolumn=0
  set nowrap

  normal! zR
  silent! normal! n

  set conceallevel=2
  set concealcursor=nvic

  let b:grepper_side = s:filename_regexp

  setfiletype GrepperSide

  syntax match GrepperSideSquareBracket /]/ contained containedin=GrepperSideSquareBrackets conceal cchar=.
  execute 'syntax match GrepperSideSquareBrackets /^]]] \v'.s:filename_regexp[20:].'/ conceal contains=GrepperSideSquareBracket'

  syntax match GrepperSideAngleBracket  /> \?/ contained containedin=GrepperSideFile conceal
  execute 'syntax match GrepperSideFile /^>>> \v'.s:filename_regexp[20:].'/ contains=GrepperSideAngleBracket'

  highlight default link GrepperSideFile Directory
endfunction

" s:side_context_next() {{{2
function! s:context_next() abort
  call search(s:filename_regexp)
  call s:side_context_scroll_into_viewport()
endfunction

" s:side_context_previous() {{{2
function! s:context_previous() abort
  call search(s:filename_regexp, 'bc')
  if line('.') == 1
    $
    call s:side_context_scroll_into_viewport()
  else
    -
  endif
  call search(s:filename_regexp, 'b')
endfunction

" s:side_context_scroll_into_viewport() {{{2
function! s:side_context_scroll_into_viewport() abort
  redraw  " needed for line('w$')
  let next_context_line = search(s:filename_regexp, 'nW')
  let current_line      = line('.')
  let last_line         = line('$')
  let last_visible_line = line('w$')
  if next_context_line > 0
    let context_length = (next_context_line - 1) - current_line
  else
    let context_length = last_line - current_line
  endif
  let scroll_length = context_length - (last_visible_line - current_line)
  if scroll_length > 0
    execute 'normal!' scroll_length."\<c-e>"
  endif
endfunction

" s:side_context_jump() {{{2
function! s:context_jump(close_window) abort
  let fileline = search(s:filename_regexp, 'bcn')
  if empty(fileline)
    return
  endif
  let [filename, line] = matchlist(getline(fileline), s:filename_regexp)[1:2]
  if a:close_window
    silent! close
    execute 'edit +'.line fnameescape(filename)
  else
    wincmd p
    execute 'edit +'.line fnameescape(filename)
    wincmd p
  endif
endfunction
" }}}1

" Operator {{{1
function! s:operator(type) abort
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
  let flags = s:get_config().operator
  let flags.query_orig = @@
  let flags.query_escaped = 0

  let flags.query = s:escape_query(flags, @@)
  if s:get_current_tool_name(flags) != 'findstr'
    let flags.query = '-- '. flags.query
  endif
  let @@ = regsave

  return s:start(flags)
endfunction

" Mappings {{{1
nnoremap <silent> <plug>(GrepperOperator) :set opfunc=<sid>operator<cr>g@
xnoremap <silent> <plug>(GrepperOperator) :<c-u>call <sid>operator(visualmode())<cr>

if hasmapto('<plug>(GrepperOperator)')
  silent! call repeat#set("\<plug>(GrepperOperator)", v:count)
endif

" Commands {{{1
command! -nargs=* -complete=customlist,grepper#complete Grepper call <sid>parse_flags(<q-args>)

for s:tool in g:grepper.tools
  let s:utool = substitute(toupper(s:tool[0]) . s:tool[1:], '-\(.\)',
        \ '\=toupper(submatch(1))', 'g')
  execute 'command! -nargs=+ -complete=file Grepper'. s:utool
        \ 'Grepper -noprompt -tool' s:tool '-query <args>'
endfor

" vim: tw=80 et sts=2 sw=2 fdm=marker
