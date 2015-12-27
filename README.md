![vim-grepper](https://raw.githubusercontent.com/mhinz/vim-grepper/master/pictures/grepper-logo.png)

[![Join the chat at https://gitter.im/mhinz/mhinz](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/mhinz/mhinz?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
[![LICENSE](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/mhinz/vim-grepper/master/LICENSE)

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
- asynchronous search with Neovim or
  [vim-dispatch](https://github.com/tpope/vim-dispatch)
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
    Plug 'tpope/vim-dispatch'  " optional
    Plug 'tpope/vim-repeat'    " optional

For the whole truth:

    :h grepper

## Examples

`:Grepper` takes a number of flags which makes it a very versatile command.

__Example 1:__

Create mappings with `:Grepper` and provide different configurations at the
same time:

```viml
nnoremap <leader>git :Grepper  -tool git -open -noswitch<cr>
nnoremap <leader>ag  :Grepper! -tool ag  -open -switch<cr>
nnoremap <leader>*   :Grepper! -tool ack -cword<cr>
```

These first two mappings will fire up the search prompt with the provided
configuration. The third one will open the prompt prepopulated with the word
under the cursor.

__Example 2:__

Use the operator to search for text from the current buffer:

```viml
nmap gs <plug>(GrepperOperator)
xmap gs <plug>(GrepperOperator)
```

`gs` in visual mode will simply prepopulate the prompt with the current visual
selection. You can also use text objects to preopulate the prompt, e.g. `gs$`
for everything from the current cursor position until the end of the line.

Everytime the prompt gets prepopulated, the query will get escaped according to
the used grep tool.

__Example 3:__

You can use `:Grepper` to build your own commmands:

```viml
command! -nargs=* -complete=file GG Grepper! -tool git -query <args>
command! -nargs=* -complete=file Ag Grepper! -tool ag -query <args>
```

Now you can use it like this: `:Ag foo` or `:GG 'foo bar' *.txt`. Mind that
`<tab>` can be used for file completion, too.

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
