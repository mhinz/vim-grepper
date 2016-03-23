[![Build Status](https://travis-ci.org/mhinz/vim-grepper.svg?branch=master)](https://travis-ci.org/mhinz/vim-grepper)

![vim-grepper](https://raw.githubusercontent.com/mhinz/vim-grepper/master/pictures/grepper-logo.png)

---

- [Intro](#intro)
- [Installation](#installation)
- [Documentation](#documentation)
- [Demo](#demo)
- [Author and Feedback](#author-and-feedback)

---

## Intro

This plugin makes searching in files easier then ever!

It supports many common grep tools
([ag](https://github.com/ggreer/the_silver_searcher),
[ack](http://beyondgrep.com), [git grep](https://git-scm.com/docs/git-grep),
[sift](https://github.com/svent/sift),
[pt](https://github.com/monochromegane/the_platinum_searcher),
[findstr](https://www.microsoft.com/resources/documentation/windows/xp/all/proddocs/en-us/findstr.mspx)
and our beloved BSD/GNU grep) out-of-the-box and it is easy to add new ones.

#### Grepper focuses on flexbility - there are many ways to use it

- **Using the prompt**: Just insert the search query or switch through the
  available grep tools.
- **Using the operator**: search for the current visual selection or motion
  right away or pre-fill the prompt with it.
- **Using the pre-defined commands**: All supported tools come with their own
  command for convenience. `:Ag 'foo bar' test/` does just what you would
  expect.
- **Build your own mappings commands**: For maximum customization simply use
  the `:Grepper` command. It is fully configurable using flags that take
  priority over options defined in your vimrc. Actually, all the default
  commands like `:Ag` etc. a built atop of `:Grepper`.

#### Additional features

- For fast and simple navigation, all found matches are either put in the
  quickfix or location list.
- [Asynchronous search with Neovim](#friendly-reminder).
- The operator action is repeatable if
  [vim-repeat](https://github.com/tpope/vim-repeat) is installed.
- Emits an User event when a search finishes, for further customization.
- The exact search command used is put in `w:quickfix_title` which is used by
  all common statusline plugins.

#### Friendly reminder

Don't use plugins just because they provide "Neovim support". Depending on their
range of duty, they might "improve" the wrong end of a task.

E.g. [vim-gitgutter](https://github.com/airblade/vim-gitgutter) might have async
Neovim support for getting the output of `git diff`, but that one returns almost
instantly anyway. The real bottleneck here is processing that output and setting
the signs using VimL, which still happens synchronously. So, use the plugin
because of its git integration, not because of hyped async support.

Neovim is no panacea (yet).

## Installation

Use your favorite plugin manager. E.g.
[vim-plug](https://github.com/junegunn/vim-plug):

    Plug 'mhinz/vim-grepper'

    " Optional: used for repeating operator actions via "."
    Plug 'tpope/vim-repeat'


## Documentation

For the whole truth: `:h grepper`.

#### Example 0

Just using `:Grepper` will use the default options. It opens a prompt and you
can use `<tab>` to switch to another tool. When matches are found, the quickfix
window opens and the cursor jumps there. If the query is empty, the word under
the cursor is used as query.

The quickfix window defines mappings for opening matches in new windows or tabs,
with and without jumping to it.

If you're used to the default behaviour of `:grep`, not opening the quickfix
window and jumping to the first match, you can change the default options:

```vim
" Mimic :grep and make ag the default tool.
let g:grepper = {
    \ 'tools': ['ag', 'git', 'grep'],
    \ 'open':  0,
    \ 'jump':  1,
    \ }
```

Related help:

    :h grepper-mappings
    :h grepper-options

#### Example 1

Create mappings for `:Grepper` with different configurations:

```vim
nnoremap <leader>git :Grepper -tool git -noswitch<cr>
nnoremap <leader>ag  :Grepper -tool ag  -grepprg ag --vimgrep -G '^.+\.txt'<cr>
nnoremap <leader>*   :Grepper -tool ack -cword -noprompt<cr>
```

The first two mappings open a prompt whereas the last one will search for the
word under the cursor right away.

Related help: `:h :Grepper`

#### Example 2

Build you own commands:

```vim
command! -nargs=* -complete=file GG Grepper -tool git -query <args>
command! -nargs=* Ag Grepper -noprompt -tool ag -grepprg ag --vimgrep <args> %
```

Now `:GG 'foo bar' *.txt` would search all text files for the string "foo bar"
and `:Ag foo` would search for "foo", but only in the current file. (Vim will
replace `%` in a command with the buffer name.)

#### Example 3

Use grepper on motions or visual selections by using the operator:

```vim
nmap gs <plug>(GrepperOperator)
xmap gs <plug>(GrepperOperator)
```

Afterwards `gs` in visual mode will simply pre-fill the prompt with the current
visual selection.

You can also use motions to prepopulate the prompt, e.g. `gs$` or `gsiw`.

**NOTE**: If you use the operator, Grepper assumes you want to search for the
exact selected text, so it gets properly escaped according to the used grep
tool. E.g. using the operator on `.*` will actually search for these 2
characters instead of "everything".

Related help: `:h grepper-operator`

## Demo

![vim-grepper](https://github.com/mhinz/vim-grepper/blob/master/pictures/grepper-demo.gif)

## Author and Feedback

If you like my plugins, please star them on Github. It's a great way of getting
feedback. Same goes for issues reports or feature requests.

Contact: [Twitter](https://twitter.com/_mhinz_)

_Get your Vim on!_
