vim9script

if exists('s:is_loaded')
  finish
endif
var is_loaded: bool = true


#######################################################################
# Usage: this and future backends like it (zip, bzip, etc.) are meant
# as a method of calling each in the same manner while keeping the Tree
# and RW scripts archive-type neutral (more work in those to do).
#
# Import: specific backend or multiple
# import autoload 'tartree/tarBackend.vim'
#
# Set Backend: can be chosen based of conditionals when multiple
# available.
# var backend: tarBackend.TarBackend = tarBackend.GnuTar.new()
# 
# Reference: as needed
# For instance, when defined inside a class: 
# var = this.backend.ExtractCmd()
#######################################################################

#######################################################################
# Method: DetectCompressionMagic
# Detects compression based on file header when ext not obvious
#######################################################################
export def DetectCompressionMagic(fname: string): string
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

#######################################################################
# Interface: TarBackend
# Caller interface
########################################################################
export interface TarBackend

  # Returns the compression type based on extension
  def DetectCompression(archive: string): string

  # Returns the ambiguous suffixes (e.g. tgz)
  def ContainerSuffix(archive: string): string

  # Returns commnd for extraction with optional decomp pipe
  def ExtractCmd(archive: string, member: string, memberDecmp: string): string

  # Decompression in place. 
  # Returns {path, kind, container, ok}: 
  # `path` is filename
  # `kind` and `container` are handed back to Recompress().
  def Decompress(archive: string): dict<any>

  # Recompression. Returns {path, ok}.
  def Recompress(path: string, kind: string, container: string): dict<any>

  # Removes `member` from archive
  def DeleteMember(archive: string, member: string): number

  # Adds/updates member to archive
  def AddMember(archive: string, member: string): number

  # Lists the member paths. Returns list or []
  def List(archive: string): list<string>
endinterface

#######################################################################
# Class: GnuTar (but not just GNU tar)
# Originally named when I had the assinine notion to create a seperate
# backend for BSD tar. 
#######################################################################
export class GnuTar implements TarBackend
  # Unambiguous extension -> kind. ('.lrp' is an old gzip'd-tar alias.)
  var extKind: dict<string> = {
      '\.bz2$': 'bzip2',
      '\.bz3$': 'bzip3',
      '\.gz$': 'gzip',
      '\.lrp$': 'gzip',
      '\.lzma$': 'lzma',
      '\.xz$': 'xz',
      '\.zst$': 'zstd',
      '\.lz4$': 'lz4',
      }

  var containerExts: list<string> = ['.tgz', '.tbz2', '.tbz', '.txz', '.tzst', '.tlz4']

  #   stream: decompress archive to stdout (extraction / listing)
  #   dcomp:  decompress archive on disk in place
  #   comp:   compress a file on disk in place
  #   pat:    regex to strip this kind's extension after decompressing
  #   ext:    extension to append after compressing
  var kinds: dict<dict<string>> = {
      gzip:  {stream: 'gzip -d -c --',  dcomp: 'gzip -d --',      comp: 'gzip --',      pat: '\.gz$',   ext: '.gz'},
      bzip2: {stream: 'bzip2 -d -c --', dcomp: 'bzip2 -d --',     comp: 'bzip2 --',     pat: '\.bz2$',  ext: '.bz2'},
      bzip3: {stream: 'bzip3 -d -c --', dcomp: 'bzip3 -d --',     comp: 'bzip3 --',     pat: '\.bz3$',  ext: '.bz3'},
      xz:    {stream: 'xz -d -c --',    dcomp: 'xz -d --',        comp: 'xz --',        pat: '\.xz$',   ext: '.xz'},
      lzma:  {stream: 'lzma -d -c --',  dcomp: 'lzma -d --',      comp: 'lzma --',      pat: '\.lzma$', ext: '.lzma'},
      zstd:  {stream: 'zstd -d -c --',  dcomp: 'zstd -d --rm --', comp: 'zstd --rm --', pat: '\.zst$',  ext: '.zst'},
      lz4:   {stream: 'lz4 -d -c --',   dcomp: 'lz4 -d --rm --',  comp: 'lz4 --rm --',  pat: '\.lz4$',  ext: '.lz4'},
      }

  def ContainerSuffix(archive: string): string
    for suf in this.containerExts
      if archive =~# '\V' .. suf .. '\$'
        return suf
      endif
    endfor
    return ''
  enddef

  def DetectCompression(archive: string): string
    for [pat, kind] in items(this.extKind)
      if archive =~# pat
        return kind
      endif
    endfor
    if this.ContainerSuffix(archive) != ''
      var magic = DetectCompressionMagic(archive)
      return magic ==# 'unknown' ? '' : magic
    endif
    return ''
  enddef

  # Fixes name starting with '-' so it can't be mistaken for an option by tar.
  def SafeName(name: string): string
    return name =~ '^\s*-' ? substitute(name, '-', './-', '') : name
  enddef

  def ExtractCmd(archive: string, member: string, memberDecmp: string): string
    var tarCmd = g:tartree_tar_cmd .. ' -' .. g:tartree_tar_readoptions .. ' '
    var safeMember = shellescape(member, 1) .. memberDecmp
    var kind = this.DetectCompression(archive)
    if kind == ''
      return tarCmd .. shellescape(this.SafeName(archive), 1) .. ' ' .. g:tar_secure .. safeMember
    endif
    return this.kinds[kind].stream .. ' ' .. shellescape(archive, 1)
        .. '| ' .. tarCmd .. '- ' .. g:tar_secure .. safeMember
  enddef

  def Decompress(archive: string): dict<any>
    var kind = this.DetectCompression(archive)
    if kind == ''
      return {path: archive, kind: '', container: '', ok: true}
    endif
    var spec = this.kinds[kind]
    system(spec.dcomp .. ' ' .. shellescape(archive, 0))
    if v:shell_error != 0
      return {path: archive, kind: kind, container: '', ok: false}
    endif
    var container = this.ContainerSuffix(archive)
    var newPath: string
    if container != ''
      newPath = substitute(archive, '\V' .. container .. '\$', '.tar', '')
    else
      newPath = substitute(archive, spec.pat, '', 'e')
    endif
    return {path: newPath, kind: kind, container: container, ok: true}
  enddef

  def Recompress(path: string, kind: string, container: string): dict<any>
    if kind == ''
      return {path: path, ok: true}
    endif
    var spec = this.kinds[kind]
    system(spec.comp .. ' ' .. shellescape(path, 0))
    if v:shell_error != 0
      return {path: path, ok: false}
    endif
    var newPath = path .. spec.ext
    if container != ''
      var finalPath = substitute(path, '\.tar$', container, 'e')
      rename(newPath, finalPath)
      newPath = finalPath
    endif
    return {path: newPath, ok: true}
  enddef

  def DeleteMember(archive: string, member: string): number
    # Note: BSD tar does not support --delete. Never go full BSD.
    # Install GNU tar (or add a BsdTar backend that does something else here).
    # TODO: implement an optional nuclear method to delete member when BSD tar
    # is used.
    system(g:tartree_tar_cmd .. ' ' .. g:tartree_tar_delfile .. ' '
        .. shellescape(archive, 0) .. g:tar_secure .. shellescape(member, 0))
    return v:shell_error
  enddef

  def AddMember(archive: string, member: string): number
    system(g:tartree_tar_cmd .. ' -' .. g:tartree_tar_writeoptions .. ' '
        .. shellescape(archive, 0) .. g:tar_secure .. shellescape(member, 0))
    return v:shell_error
  enddef

  def List(archive: string): list<string>
    var kind = this.DetectCompression(archive)
    var output: list<string>
    if kind == ''
      output = systemlist(g:tartree_tar_cmd .. ' -' .. g:tartree_tar_browseoptions .. ' '
          .. shellescape(this.SafeName(archive), 0))
    else
      output = systemlist(this.kinds[kind].stream .. ' ' .. shellescape(archive, 0)
          .. '| ' .. g:tartree_tar_cmd .. ' -' .. g:tartree_tar_browseoptions .. ' -')
    endif
    if v:shell_error != 0
      return []
    endif
    return output
  enddef
endclass
