# TarTree

A simple tree browser to view/edit files within a tar archive.

![TarTree Screenshot](ScreenShot.png)

# Requirements

TarTree was written in vim9script and thus depends on Vim 9. Built and tested on Vim 9.2.

# Installation

Use your favorite plugin manager

## Examples

### Vundle

Add this to your .vimrc

```vim
Plugin 'Galvarcus/TarTree'
```
Then run `:PluginInstall`

### Vim-Plug

Add this to your .vimrc

```vim
Plug 'Galvarcus/TarTree'
```

Then run `:PlugInstall`

# Usage

`:TarTree PATH_TO_TAR_FILE`

Opens the tarfile in a tree view split similar to Netrw or NERDTree with the following command options:

- ?
  - opens/closes help text view
- o, <CR>
  - opens the current selected file or toggles a directory
- r
  - refreshes the tree
- q
  - quits the tree

`:TarTreeToggle`

Toggles on/off the tree view

`:TarTreeClose`

Closes the TarTree pane

# Operating System Caveats

## Linux

None

## MacOS and BSD variants

BSD tar does not support `--delete` and will not allow for editing of files in the archive.

### Install GNU Tar

1. Homebrew: `brew install gnu-tar`
2. MacPorts: `sudo port install gnutar`

- Follow the instructions for adding GNU tar to your PATH environmental variable in `~/.bashrc`
  - E.g. 
```bash
PATH="/usr/local/opt/gnu-tar/libexec/gnubin:$PATH"
```
- Or, set `g:tartree_tar_cmd` to the full path to the tar executable in your `~/.vimrc`
  - E.g.
```vim
g:tartree_tar_cmd = '/usr/local/opt/gnu-tar/libexec/gnubin/tar`
```

## Windows/Cygwin

All efforts have been made to account for Windows-centric commands; however, I do not have access to Windows for testing and I am sure something was missed. You can help by testing and submitting an issue here.

# Global Variables

To customize TarTree, set the following global variables in your `~/vimrc` prefixed with `let ` for legacy .vimrc. 

`g:tartree_win_width`

Sets the width of the TarTree vsplit
Default: 31

`g:tartree_show_hidden`

- 1 to list dot files
- 0 (default) to hide dot files

`g:tartree_arrow_open`

Character to display next to open directories, e.g. '-'
Default: '▾ '

`g:tartree_arrow_closed`

Character to display next to closed directories, e.g. '+'
 Default: '▸ '

`g:tartree_auto_open`

Option to enable TarTree to list a tar file opened with `:e` 

- 1 to enable
- 0 (default) to disable

`g:tartree_tar_cmd`

Tar executable full path or command in your $PATH. Defaults to 'tar'

# Motivation

TarTree was initially part of another niche vim9script project. About halfway through I decided to branch this component off for use by others. And, as with most other small projects throughout my career, morphed into a bit more than originally intended.

# Acknowledements

The following have either directly or indirectly inspired this project.

## [NERDTree](https://github.com/preservim/nerdtree)

My personal favorite vim directory browser. Only second to my favorite CLI directory browser [Midnight Commander](https://midnight-commander.org/)

## [Vim's internal tar plugin](https://github.com/vim/vim/blob/master/runtime/autoload/tar.vim)

`autoload/tartree/tartreeRW.vim` is a partial refactoring of the tar.vim, particularly `tar#Read()` and `tar#Write`.
`autoload/tartree.vim` is a reimagining of `tar#Browse()` and `TarBrowseSelect()`




