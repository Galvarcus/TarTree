vim9script

if exists('s:is_loaded')
  finish
endif
var is_loaded: bool = true

#######################################################################
# NOTICE: This is a stripped, modified, Vim9 OOP class rewrite of Vim's
# runtime/autoload/tar.vim. Original license retained below, sans
# changelog. See https://github.com/vim/vim
#
# AI Notice: refactored into Vim9 OOP class with AI assistance. 
# (Ask for which one, as adverts have no place here.)
#######################################################################
# Original Header: with Copyright Notice
# 
# tar.vim: Handles browsing tarfiles - AUTOLOAD PORTION
# Version:      32b-oop (class-based rewrite)
# License:      Vim License  (see vim's :help license)
#
#       Contains many ideas from Michael Toren's <tar.vim>
#
# Copyright:    Copyright (C) 2005-2017 Charles E. Campbell
#               Permission is hereby granted to use and distribute this code,
#               with or without modifications, provided that this copyright
#               notice is copied with it. Like anything else that's free,
#               tar.vim and tarPlugin.vim are provided *as is* and comes
#               with no warranty of any kind, either expressed or implied.
#               By using this plugin, you agree that in no event will the
#               copyright holder be liable for any damages resulting from
#               the use of this software.
#######################################################################


#######################################################################
#  Default Settings: 
#  Global variables moved to import/variables/globals.vim


#######################################################################
# Class: Tar 
####################################################################### 
export class Tar
  # Buffer-local persisted state (survives the buffer being renamed,
  # so Write() can be called later without needing the pseudo-name
  # or an autocommand at all).
  var archivePath: string = ''
  var fileName: string = ''
  var curdir: string = ''
  var tmpdir: string = ''
  var remoteUrl: string = ''

  def new(this.archivePath = v:none, this.fileName = v:none)
  enddef
  
  ###############################################################
  # Entry Point: opens a new window on one file from the archive.
  ############################################################### 
  static def CreateWindow(archivePath: string, fileName: string)
    noswapfile new
    if !exists('g:tar_nomax') || g:tar_nomax == 0
      wincmd _
    endif
    var tar = Tar.new(archivePath, fileName)
    tar.Read()
  enddef

  ###############################################################
  # Method: WriteCurrent
  # Writes the *current* buffer back into whichever archive/file
  # it was originally read from, using the state stashed in b: at
  # Read() time.
  ############################################################### 
  static def WriteCurrent()
    if !exists('b:tar_archive') || !exists('b:tar_filename')
      Tar.Msg('WriteCurrent', 'error', 'this buffer has no associated tar filename')
      return
    endif
    var tar = Tar.new(b:tar_archive, b:tar_filename)
    tar.curdir = get(b:, 'tar_curdir', getcwd())
    tar.tmpdir = get(b:, 'tar_tmpdir', tempname())
    tar.remoteUrl = get(b:, 'tar_remote', '')
    tar.Write()
  enddef

  ###############################################################
  # Method: Read
  # Reads the contents from the archive and sets b: variables
  # for use by Write().
  ############################################################### 
  def Read()
    var repkeep = &report
    &report = 10

    # be careful not to execute specially crafted paths
    var escapeFile = this.fileName
        ->substitute(g:tar_leading_pat, '', '')
        ->fnameescape()

    this.curdir = getcwd()
    var tmp = tempname()
    if tmp =~ '\.'
      tmp = substitute(tmp, '\.[^.]*$', '', 'e')
    endif
    this.tmpdir = tmp
    mkdir(this.tmpdir, 'p')

    try
      exe 'lcd ' .. fnameescape(this.tmpdir)
    catch /^Vim\%((\a\+)\)\=:E344/
      Tar.Msg('Read', 'error', 'cannot lcd to temporary directory')
      &report = repkeep
      return
    endtry

    if isdirectory('_ZIPVIM_')
      Tar.Rmdir('_ZIPVIM_')
    endif
    mkdir('_ZIPVIM_', 'p')
    lcd _ZIPVIM_

    var archive = this.archivePath
    if has('win32unix') && executable('cygpath')
      archive = substitute(system('cygpath -u ' .. shellescape(archive, 0)), '\n$', '', 'e')
    endif

    # extra decompression needed for the archive file
    # TODO: Move this and the similar section in Write() to an independent method/class.
    var decmp = ''
    var doro = false
    if this.fileName =~ '\.bz2$' && executable('bzcat')
      decmp = '|bzcat'
      doro = true
    elseif this.fileName =~ '\.bz3$' && executable('bz3cat')
      decmp = '|bz3cat'
      doro = true
    elseif this.fileName =~ '\.t\=gz$' && executable('zcat')
      decmp = '|zcat'
      doro = true
    elseif this.fileName =~ '\.lzma$' && executable('lzcat')
      decmp = '|lzcat'
      doro = true
    elseif this.fileName =~ '\.xz$' && executable('xzcat')
      decmp = '|xzcat'
      doro = true
    elseif this.fileName =~ '\.zst$' && executable('zstdcat')
      decmp = '|zstdcat'
      doro = true
    elseif this.fileName =~ '\.lz4$' && executable('lz4cat')
      decmp = '|lz4cat'
      doro = true
    else
      if this.fileName =~ '\.bz2$\|\.bz3$\|\.gz$\|\.lzma$\|\.xz$\|\.zip$\|\.Z$'
        setlocal binary
      endif
    endif

    if archive =~# '\.bz2$'
      exe 'sil! r! bzip2 -d -c -- ' .. shellescape(archive, 1)
          .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
          .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
      exe 'read ' .. escapeFile
    elseif archive =~# '\.bz3$'
      exe 'sil! r! bzip3 -d -c -- ' .. shellescape(archive, 1)
          .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
          .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
      exe 'read ' .. escapeFile
    elseif archive =~# '\.gz$'
      exe 'sil! r! gzip -d -c -- ' .. shellescape(archive, 1)
          .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
          .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
      exe 'read ' .. escapeFile
    elseif archive =~# '\.tgz$\|\.tbz$\|\.txz$'
      var kind = Tar.Header(archive)
      if kind ==? 'bzip2'
        exe 'sil! r! bzip2 -d -c -- ' .. shellescape(archive, 1)
            .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
            .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
        exe 'read ' .. escapeFile
      elseif kind ==? 'bzip3'
        exe 'sil! r! bzip3 -d -c -- ' .. shellescape(archive, 1)
            .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
            .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
        exe 'read ' .. escapeFile
      elseif kind ==? 'xz'
        exe 'sil! r! xz -d -c -- ' .. shellescape(archive, 1)
            .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
            .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
        exe 'read ' .. escapeFile
      elseif kind ==? 'zstd'
        exe 'sil! r! zstd --decompress --stdout -- ' .. shellescape(archive, 1)
            .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
            .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
        exe 'read ' .. escapeFile
      elseif kind ==? 'gzip'
        exe 'sil! r! gzip -d -c -- ' .. shellescape(archive, 1)
            .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
            .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
        exe 'read ' .. escapeFile
      endif
    elseif archive =~# '\.lrp$'
      exe 'sil! r! cat -- ' .. shellescape(archive, 1) .. ' | gzip -d -c - | '
          .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
          .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
      exe 'read ' .. escapeFile
    elseif archive =~# '\.lzma$'
      exe 'sil! r! lzma -d -c -- ' .. shellescape(archive, 1)
          .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
          .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
      exe 'read ' .. escapeFile
    elseif archive =~# '\.xz$\|\.txz$'
      exe 'sil! r! xz --decompress --stdout -- ' .. shellescape(archive, 1) .. ' | '
          .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
          .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
      exe 'read ' .. escapeFile
    elseif archive =~# '\.lz4$\|\.tlz4$'
      exe 'sil! r! lz4 --decompress --stdout -- ' .. shellescape(archive, 1) .. ' | '
          .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' - '
          .. g:tar_secure .. shellescape(this.fileName, 1) .. decmp
      exe 'read ' .. escapeFile
    else
      if archive =~ '^\s*-'
        # a name starting with a dash could be taken as an option
        archive = substitute(archive, '-', './-', '')
      endif
      exe 'silent r! ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' '
          .. shellescape(archive, 1) .. ' ' .. g:tar_secure
          .. shellescape(this.fileName, 1) .. decmp
      exe 'read ' .. escapeFile
    endif

    redraw!

    if v:shell_error != 0
      lcd ..
      Tar.Rmdir('_ZIPVIM_')
      exe 'lcd ' .. fnameescape(this.curdir)
      &report = repkeep
      Tar.Msg('Read', 'error', $'sorry, unable to open or extract {archive} with {this.fileName}')
      return
    endif

    if doro
      # reverse process (recompressing a changed member) isn't supported
      setlocal readonly
    endif

    # stash state on the buffer
    b:tar_archive = this.archivePath
    b:tar_filename = this.fileName
    b:tar_curdir = this.curdir
    b:tar_tmpdir = this.tmpdir
    b:tar_remote = this.remoteUrl

    # cleanup
    keepjumps sil! :0delete
    set nomodified

    &report = repkeep
    exe 'lcd ' .. fnameescape(this.curdir)

    # Cosmetic name for the window title
    silent exe 'file ' .. fnamemodify(fnameescape(this.archivePath), ":t") .. '::' .. fnameescape(this.fileName)

    # Hijack :w, et al. for WriteCurrent().
    setlocal buftype=acwrite
    autocmd! TarClass BufWriteCmd,FileWriteCmd <buffer>
    autocmd TarClass BufWriteCmd,FileWriteCmd <buffer> TarWriteCmd()

    filetype detect
    set nomodified
  enddef

  ###############################################################
  # Method: Write
  ############################################################### 
  def Write()
    if this.archivePath == ''
      this.archivePath = get(b:, 'tar_archive', '')
      this.fileName = get(b:, 'tar_filename', '')
    endif
    if this.archivePath == '' || this.fileName == ''
      Tar.Msg('Write', 'error', 'no tar archive/filename associated with this buffer')
      return
    endif
    if this.curdir == ''
      this.curdir = get(b:, 'tar_curdir', getcwd())
    endif
    if this.tmpdir == ''
      this.tmpdir = get(b:, 'tar_tmpdir', tempname())
    endif

    var pwdkeep = getcwd()
    var repkeep = &report
    &report = 10

    if !executable(g:tartree_tar_cmd)
      redraw!
      &report = repkeep
      Tar.Msg('Write', 'error', $'{g:tartree_tar_cmd} is not executable')
      return
    endif

    var archive = this.archivePath
    var filename = this.fileName

    if !isdirectory(this.tmpdir)
      mkdir(this.tmpdir, 'p')
    endif
    exe 'lcd ' .. fnameescape(this.tmpdir)
    if isdirectory('_ZIPVIM_')
      Tar.Rmdir('_ZIPVIM_')
    endif
    mkdir('_ZIPVIM_', 'p')
    lcd _ZIPVIM_
    var dir = fnamemodify(filename, ':p:h')
    if dir !~# '_ZIPVIM_$'
      mkdir(dir, 'p')
    endif

    # handle compressed archives; empty compress == "nothing to recompress"
    var compress = ''
    var tgz = false
    if archive =~# '\.bz2$'
      system('bzip2 -d -- ' .. shellescape(archive, 0))
      archive = substitute(archive, '\.bz2$', '', 'e')
      compress = 'bzip2 -- ' .. shellescape(archive, 0)
    elseif archive =~# '\.bz3$'
      system('bzip3 -d -- ' .. shellescape(archive, 0))
      archive = substitute(archive, '\.bz3$', '', 'e')
      compress = 'bzip3 -- ' .. shellescape(archive, 0)
    elseif archive =~# '\.tgz$'
      system('gzip -d -- ' .. shellescape(archive, 0))
      archive = substitute(archive, '\.tgz$', '.tar', 'e')
      compress = 'gzip -- ' .. shellescape(archive, 0)
      tgz = true
    elseif archive =~# '\.gz$'
      system('gzip -d -- ' .. shellescape(archive, 0))
      archive = substitute(archive, '\.gz$', '', 'e')
      compress = 'gzip -- ' .. shellescape(archive, 0)
    elseif archive =~# '\.xz$'
      system('xz -d -- ' .. shellescape(archive, 0))
      archive = substitute(archive, '\.xz$', '', 'e')
      compress = 'xz -- ' .. shellescape(archive, 0)
    elseif archive =~# '\.zst$'
      system('zstd --decompress --rm -- ' .. shellescape(archive, 0))
      archive = substitute(archive, '\.zst$', '', 'e')
      compress = 'zstd --rm -- ' .. shellescape(archive, 0)
    elseif archive =~# '\.lz4$'
      system('lz4 --decompress --rm -- ' .. shellescape(archive, 0))
      archive = substitute(archive, '\.lz4$', '', 'e')
      compress = 'lz4 --rm -- ' .. shellescape(archive, 0)
    elseif archive =~# '\.lzma$'
      system('lzma -d -- ' .. shellescape(archive, 0))
      archive = substitute(archive, '\.lzma$', '', 'e')
      compress = 'lzma -- ' .. shellescape(archive, 0)
    endif
    # Note: no support for name.tar.tbz/.txz/.tlz4/.tzst

    if v:shell_error != 0
      Tar.Msg('Write', 'error', $'sorry, unable to update {archive} with {filename}')
      lcd ..
      Tar.Rmdir('_ZIPVIM_')
      exe 'lcd ' .. fnameescape(pwdkeep)
      &report = repkeep
      return
    endif

    if filename =~ '/'
      var dirpath = substitute(filename, '/[^/]\+$', '', 'e')
      if has('win32unix') && executable('cygpath')
        dirpath = substitute(system('cygpath ' .. shellescape(dirpath, 0)), '\n', '', 'e')
      endif
      mkdir(dirpath, 'p')
    endif
    if archive !~ '/'
      archive = this.curdir .. '/' .. archive
    endif
    if archive =~ '^\s*-'
      archive = substitute(archive, '-', './-', '')
    endif

    # don't overwrite a file forcefully
    # Fix: for an E344 issue with the temp dir
    # Drop back to a normal buffer for just this one write,
    # then restore acwrite + the handler immediately after.
    var buftypeKeep = &l:buftype
    setlocal buftype=
    autocmd! TarClass BufWriteCmd,FileWriteCmd <buffer>
    exe 'w ' .. fnameescape(filename)
    &l:buftype = buftypeKeep
    autocmd TarClass BufWriteCmd,FileWriteCmd <buffer> TarWriteCmd()

    if has('win32unix') && executable('cygpath')
      archive = substitute(system('cygpath ' .. shellescape(archive, 0)), '\n', '', 'e')
    endif

    # delete old member from archive
    # Note: BSD tar does not support --delete
    # Never go full BSD. Install GNU tar
    system(g:tartree_tar_cmd .. ' ' .. g:tartree_tar_delfile .. ' ' .. shellescape(archive, 0) .. g:tar_secure .. shellescape(filename, 0))
    if v:shell_error != 0
      Tar.Msg('Write', 'error', $'sorry, unable to update {fnameescape(archive)} with {fnameescape(filename)} --delete not supported?')
    else
      # add the updated member back in
      system(g:tartree_tar_cmd .. ' -' .. g:tartree_tar_writeoptions .. ' ' .. shellescape(archive, 0) .. g:tar_secure .. shellescape(filename, 0))
      if v:shell_error != 0
        Tar.Msg('Write', 'error', $'sorry, unable to update {fnameescape(archive)} with {fnameescape(filename)}')
      elseif compress != ''
        system(compress)
        if tgz
          rename(archive .. '.gz', substitute(archive, '\.tar$', '.tgz', 'e'))
        endif
      endif
    endif

    # Network support for write
    if this.remoteUrl =~ '^\a\+://'
      var remote = this.remoteUrl
      :1split | noswapfile enew
      var binkeep = &l:binary
      var eikeep = &eventignore
      set binary eventignore=all
      exe 'noswapfile e! ' .. fnameescape(archive)
      netrw#NetWrite(remote)
      &eventignore = eikeep
      &l:binary = binkeep
      q!
    endif

    lcd ..
    Tar.Rmdir('_ZIPVIM_')
    exe 'lcd ' .. fnameescape(pwdkeep)
    setlocal nomodified

    &report = repkeep
  enddef

  ###############################################################
  # Helpers:
  # # TODO: Move some or all to external class/methods for reuse
  ############################################################### 

  ###############################################################
  # Method: Msg
  # message handler
  ############################################################### 
  static def Msg(func: string, severity: string, msg: string)
    redraw!
    if severity =~? 'error'
      echohl Error
    else
      echohl WarningMsg
    endif
    echom $'***{severity}*** ({func}) {msg}'
    echohl None
  enddef
  ###############################################################
  # Method: Rmdir
  # does exactly what you think it does
  ############################################################### 
  static def Rmdir(dir: string)
    if isdirectory(dir)
      delete(dir, 'rf')
    endif
  enddef
  ###############################################################
  # Method: Header
  # Examines file header for compression detection
  ############################################################### 
  static def Header(fname: string): string
    var header = readblob(fname, 0, 6)
    if header[0 : 2] == str2blob(['BZh'])                  # bzip2
      return 'bzip2'
    elseif header[0 : 2] == str2blob(['BZ3'])               # bzip3
      return 'bzip3'
    elseif header == str2blob(["\xfd7zXZ\n"])               # xz
      return 'xz'
    elseif header[0 : 3] == str2blob(["\x28\xb5\x2f\xfd"])  # zstd
      return 'zstd'
    elseif header[0 : 3] == str2blob(["\x04\x22\x4d\x18"])  # lz4
      return 'lz4'
    elseif header[0 : 1] == str2blob(["\x1f\x9d"])
        || header[0 : 1] == str2blob(["\x1f\x8b"])
        || header[0 : 1] == str2blob(["\x1f\x9e"])
        || header[0 : 1] == str2blob(["\x1f\xa0"])
        || header[0 : 1] == str2blob(["\x1f\x1e"])          # gzip variants
      return 'gzip'
    endif
    return 'unknown'
  enddef
endclass

#######################################################################
# Externals:
####################################################################### 

# Register the per-buffer augroup name.
augroup TarClass
augroup END

# External entry points 
export def CreateWindow(archivePath: string, fileName: string)
  Tar.CreateWindow(archivePath, fileName)
enddef

# Workaround: E1017
def TarWriteCmd()
  Tar.WriteCurrent()
enddef

