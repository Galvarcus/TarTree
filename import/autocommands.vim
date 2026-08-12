vim9script


import './variables/globals.vim'
import autoload 'tartree.vim'

var TAO: bool = g:tartree_auto_open

# Kludge: override the autocommand group for Vim's internal tar plugin
# in order to avoid clashes.
# TODO: Add flags in autoload/tartree.vim to allow fallback to Vim's internal
# tar plugin per archive type using global user-defined variables.

if TAO
  augroup tar
    autocmd!
    au BufReadCmd   tarfile::*	call tar#Read(expand("<amatch>"))
    au FileReadCmd  tarfile::*	call tar#Read(expand("<amatch>"))
    au BufWriteCmd  tarfile::*	call tar#Write(expand("<amatch>"))
    au FileWriteCmd tarfile::*	call tar#Write(expand("<amatch>"))

    if has("unix")
      au BufReadCmd   tarfile::*/*	call tar#Read(expand("<amatch>"))
      au FileReadCmd  tarfile::*/*	call tar#Read(expand("<amatch>"))
      au BufWriteCmd  tarfile::*/*	call tar#Write(expand("<amatch>"))
      au FileWriteCmd tarfile::*/*	call tar#Write(expand("<amatch>"))
    endif

    au BufReadCmd   *.cbt			call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.lrp			call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tar			call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tar.bz2		call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tar.bz3		call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tar.gz		call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tar.lz4		call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tar.lzma		call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tar.xz		call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tar.Z		call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tar.zst		call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tbz			call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tgz			call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tlz4		call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.txz			call tartree.AutoOpen(expand("<amatch>"))
    au BufReadCmd   *.tzst		call tartree.AutoOpen(expand("<amatch>"))
  augroup END
endif

