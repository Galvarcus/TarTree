vim9script

if exists('s:is_loaded')
  finish
endif
var is_loaded: bool = true

# Logger
import 'Logger/logger.vim' as Log
var log = Log.Logger.new('TarTree', expand('<sfile>:t'))

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

import autoload 'tartree/archiveBackend.vim' as AB
import autoload 'tartree/archiveRegistry.vim' as Registry
import autoload 'tartree/tarBackend.vim' as TB

#######################################################################
# Class: Tar 
####################################################################### 
export class Tar
  var archivePath: string = ''
  var fileName: string = ''
  var curdir: string = ''
  var tmpdir: string = ''
  var remoteUrl: string = ''

  var backend: AB.ArchiveBackend = TB.GnuTar.new()

  def new(this.archivePath = v:none, this.fileName = v:none, this.backend = v:none)
  enddef

  ###############################################################
  # Entry Point: opens a new window on one file from the archive.
  ############################################################### 
  static def CreateWindow(archivePath: string, fileName: string, backend: AB.ArchiveBackend = TB.GnuTar.new())
    noswapfile new
    if !exists('g:tar_nomax') || g:tar_nomax == 0
      wincmd _
    endif
    var tar = Tar.new(archivePath, fileName, backend)
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
      Log.Error('This buffer has no associated tar filename.')
      return
    endif
    var archiveType = AB.ArchiveTypeDetect(b:tar_archive)
    var backend: AB.ArchiveBackend
    try
      backend = Registry.NewBackend(archiveType)
    catch
      Log.Error('no backend for archive type "' .. archiveType .. '":' .. b:tar_archive})
      return
    endtry
    var tar = Tar.new(b:tar_archive, b:tar_filename, backend)
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
      Log.Error('Cannot lcd to temporary directory')
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

    # A member can be a compressed file *in its own right* (e.g. a
    # ".gz" stored inside the tarball) -- that needs an extra pipe
    # stage on top of the extraction. This is unrelated to the
    # archive's own compression, which this.backend handles.
    var memberDecmp = ''
    var doro = false
    if this.fileName =~ '\.bz2$' && executable('bzcat')
      memberDecmp = '|bzcat'
      doro = true
    elseif this.fileName =~ '\.bz3$' && executable('bz3cat')
      memberDecmp = '|bz3cat'
      doro = true
    elseif this.fileName =~ '\.t\=gz$' && executable('zcat')
      memberDecmp = '|zcat'
      doro = true
    elseif this.fileName =~ '\.lzma$' && executable('lzcat')
      memberDecmp = '|lzcat'
      doro = true
    elseif this.fileName =~ '\.xz$' && executable('xzcat')
      memberDecmp = '|xzcat'
      doro = true
    elseif this.fileName =~ '\.zst$' && executable('zstdcat')
      memberDecmp = '|zstdcat'
      doro = true
    elseif this.fileName =~ '\.lz4$' && executable('lz4cat')
      memberDecmp = '|lz4cat'
      doro = true
    else
      if this.fileName =~ '\.bz2$\|\.bz3$\|\.gz$\|\.lzma$\|\.xz$\|\.zip$\|\.Z$'
        setlocal binary
      endif
    endif

    exe 'sil! r! ' .. this.backend.ExtractCmd(archive, this.fileName, memberDecmp)
    exe 'read ' .. escapeFile

    redraw!

    if v:shell_error != 0
      lcd ..
        Tar.Rmdir('_ZIPVIM_')
      exe 'lcd ' .. fnameescape(this.curdir)
      &report = repkeep
      Log.Error('Unable to open or extract ' .. archive .. ' with ' .. this.fileName)
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
      Log.Error('No tar archive/filename associated with this buffer')
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
      Log.Error(g:tartree_tar_cmd .. ' is not executable')
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

    # Decompress the archive on disk (no-op if it isn't compressed).
    # `kind`/`container` are threaded through to Recompress() below.
    var dec = this.backend.Decompress(archive)
    if !dec.ok
      Log.Error('Unable to update ' .. archive .. ' with ' .. filename)
      lcd ..
        Tar.Rmdir('_ZIPVIM_')
      exe 'lcd ' .. fnameescape(pwdkeep)
      &report = repkeep
      return
    endif
    archive = dec.path
    var kind = dec.kind
    var container = dec.container

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

    # delete old member from archive, then add the updated one back in
    var delErr = this.backend.DeleteMember(archive, filename)
    if delErr != 0
      Log.Error('Unable to update ' .. fnameescape(archive) .. ' with ' .. fnameescape(filename) .. ' --delete not supported?')
    else
      var addErr = this.backend.AddMember(archive, filename)
      if addErr != 0
        Log.Error('Unable to update ' .. fnameescape(archive) .. ' with ' .. fnameescape(filename))
      elseif kind != ''
        var rec = this.backend.Recompress(archive, kind, container)
        if !rec.ok
          Log.Error('Unable to recompress ' .. fnameescape(archive))
        else
          archive = rec.path
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
  ############################################################### 

  ###############################################################
  # Method: Rmdir
  # does exactly what you think it does
  ############################################################### 
  static def Rmdir(dir: string)
    if isdirectory(dir)
      delete(dir, 'rf')
    endif
  enddef
endclass

#######################################################################
# Externals:
####################################################################### 

# Register the per-buffer augroup name.
augroup TarClass
augroup END

# External entry points 
export def CreateWindow(archivePath: string, fileName: string, backend: AB.ArchiveBackend = TB.GnuTar.new())
  Tar.CreateWindow(archivePath, fileName, backend)
enddef

# Workaround: E1017
def TarWriteCmd()
  Tar.WriteCurrent()
enddef
