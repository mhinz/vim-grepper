[![Build Status](https://travis-ci.org/mhinz/vim-grepper.svg?branch=master)](https://travis-ci.org/mhinz/vim-grepper)
[![LICENSE](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/mhinz/vim-grepper/master/LICENSE)

![vim-grepper](https://raw.githubusercontent.com/mhinz/vim-grepper/master/pictures/grepper-logo.png)

---

- [Intro](#intro)
- [Installation & Documentation](#installation-and-documentation)
- [Examples](#examples)
- [Demo](#demo)
- [Author and Feedback](#author-and-feedback)

---

## Intro

This plugin is a convenience wrapper around `'grepprg'` and `'grepformat'`,
supports most common grep tools, and is easily extendable. It exposes a single
command: `:Grepper`.

You choose a grep tool, enter a search term, and get your matches into a
quickfix list.

_Features:_

- supports by default: **git**, **ag**, **sift**, **pt**, **ack**, **grep**,
  **findstr**
- quick switching between grep tools
- adding new grep tools or replacing parameters of default ones is easy
- asynchronous search with Neovim
- operator for selecting search queries by motion
- operator action is repeatable if
  [vim-repeat](https://github.com/tpope/vim-repeat) is installed
- `:Grepper` takes flags that overrule options (thus you can use different
  mappings for different configurations)
- emits an User event when a search finishes, for further customization
- support for proper statusline plugins

## Installation and Documentation

Use your favorite plugin manager.

Using [vim-plug](https://github.com/junegunn/vim-plug):

    Plug 'mhinz/vim-grepper'

    " Optional: used for repeating operator actions via "."
    Plug 'tpope/vim-repeat'

For the whole truth:

    :h grepper

## Examples

We only need one command, since `:Grepper` can be configured on-the-fly using
flags.

__Example 0:__

Just using `:Grepper` will use the default options. It opens a prompt and you
can use `<tab>` to switch to another tool. When matches are found, the quickfix
window opens and the cursor jumps there. If the query is empty, the word under
the cursor is used as query.

The quickfix window defines mappings for opening matches in new windows or tabs,
with and without jumping to it.

If you're used to the default behaviour of `:grep`, not opening the quickfix
window and jumping to the first match, you can change the default options:

```viml
" Mimic :grep and make ag the default tool.
let g:grepper = {
    \ 'tools': ['ag', 'git', 'grep'],
    \ 'open':  0,
    \ 'jump':  1,
    \ }
```

Related help:

```
:h grepper-mappings`
:h grepper-options`
```

__Example 1:__

Create mappings for `:Grepper` with different configurations:

```viml
nnoremap <leader>git :Grepper -tool git -noswitch<cr>
nnoremap <leader>ag  :Grepper -tool ag  -grepprg ag --vimgrep -G '^.+\.txt'<cr>
nnoremap <leader>*   :Grepper -tool ack -cword -noprompt<cr>
```

The first two mappings open a prompt whereas the last one will search for the
word under the cursor right away.

Related help: `:h :Grepper`

__Example 2:__

Build you own commands:

```viml
command! -nargs=* -complete=file GG Grepper -tool git -query <args>
command! -nargs=* Ag Grepper -noprompt -tool ag -grepprg ag --vimgrep <args> %
```

Now `:GG 'foo bar' *.txt` would search all text files for the string "foo bar"
and `:Ag foo` would search for "foo", but only in the current file. (Vim will
replace `%` in a command with the buffer name.)

__Example 3:__

Use can use grepper on motions or in visual mode by mapping the operator:

```viml
nmap gs <plug>(GrepperOperator)
xmap gs <plug>(GrepperOperator)
```

Afterwards `gs` in visual mode will simply prepopulate the prompt with the
current visual selection.

You can also use motions to prepopulate the prompt, e.g. `gs$` or `gsiw`.

The prompt gets prepopulated and the query will get escaped according to the
used grep tool.

Related help: `:h grepper-operator`

## Demo

![vim-grepper](https://github.com/mhinz/vim-grepper/blob/master/pictures/grepper-demo.gif)

## Author and Feedback

If you like my plugins, please star them on Github. It's a great way of getting
feedback. Same goes for issues reports or feature requests.

Contact:
[Mail](mailto:mh.codebro@gmail.com) |
[Twitter](https://twitter.com/_mhinz_) |
[Gitter](https://gitter.im/mhinz/mhinz)

_Get your Vim on!_
