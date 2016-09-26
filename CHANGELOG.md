# Change Log

All notable changes to this project will be documented in this file. (Thus, it
won't list single bugfixes or improved documentation.)

## [Unreleased]

## [1.3] - 2016-09-26

### Added

- Async support for Vim.
- Default commands for all supported tools: `:Grep` for grep, `:Ack` for ack,
  etc. Only exception: `:GG` for `git` to avoid conflicts with
  [fugitive](https://github.com/tpope/vim-fugitive).
- Support for [ripgrep](https://github.com/BurntSushi/ripgrep)
- `-noprompt` flag. Especially useful together with `-grepprg` or `-cword`.
- `-highlight` flag that enables search highlighting for simple queries.
- Flag completion for `:Grepper`. Compare `:Grepper <c-d>` to `:Grepper -<c-d>`.
- `$+` placeholder for `-grepprg`. Gets replaced by all opened files.
- `$.` placeholder for `-grepprg`. Gets replaced by the current buffer name.

### Changed

- Use stdout handler instead of tempfile for async output.
- Use `'nowrap'` in quickfix window.
- When using `-cword`, add the query to the input history.
- `&grepprg` does not get touched anymore.

### Removed

- Quickfix mappings in favor of dedicated plugins like [vim-qf](https://github.com/romainl/vim-qf) or [QFEnter](https://github.com/yssl/QFEnter).
- `-cword!`. Was inconsistent syntax in the first place and can now be replaced
  with `-cword -noprompt`.
- Support for vim-dispatch. See this
  [commit](https://github.com/mhinz/vim-grepper/commit/c345137c336c531209a6082a6fcd5c2722d45773).
- Sift was removed as default tool, because it either needs `grepprg = 'sift $*
  .'` (which makes restricting the search to a subdirectory quite hard) or an
  allocated PTY (which means fighting with all kinds of escape sequences). If
  you're a Go nut, use
  [pt](https://github.com/monochromegane/the_platinum_searcher) instead.

## [1.2] - 2016-01-23

This is mainly a bugfix release and the last release before 2.0 that will bring
quite some changes.

### Changed

- The default order of the tools is this now: `['ag', 'ack', 'grep', 'findstr',
  'sift', 'pt', 'git']`. This was done because not everyone is a git nut like
  me.

## [1.1] - 2016-01-18

50 commits.

### Added

- `CHANGELOG.md` according to [keepachangelog.com](http://keepachangelog.com)
- Support for [sift](https://sift-tool.org)
- `<esc>` can be used to cancel the prompt now (in addition to `<c-c>`)
- `-grepprg` flag (allows more control about the exact command used)
- For ag versions older than 0.25, `--column --nogroup --noheading` is used
  automatically instead of `--vimgrep`
- FAQ (see `:h grepper-faq`)
- Mappings in quickfix window: `o`, `O`, `S`, `v`, `V`, `T` (see `:h
  grepper-mappings`)
- using `-dispatch` implies `-quickfix`
- The quickfix window uses the full width at the bottom of the screen. Location
  lists are opened just below their accompanying windows instead.

### Changed

- Option "open" enabled by default
- Option "switch" enabled by default
- Option "jump" disabled by default
- The "!" for :Grepper was removed. Use `:Grepper -jump` instead.
- improved vim-dispatch support
- `g:grepper.tools` had to contain executables before. It takes arbitrary names
  now.
- Never forget query when switching tools (previously we remembered the query
  only when the operator was used)

## [1.0] - 2015-12-09

First release!

[Unreleased]: https://github.com/mhinz/vim-grepper/compare/v1.3...HEAD
[1.3]: https://github.com/mhinz/vim-grepper/compare/v1.2...v1.3
[1.2]: https://github.com/mhinz/vim-grepper/compare/v1.1...v1.2
[1.1]: https://github.com/mhinz/vim-grepper/compare/v1.0...v1.1
[1.0]: https://github.com/mhinz/vim-grepper/compare/8b9234f...v1.0
