vim9script

#######################################################################
# Interface: archiveBackend
#
# Usage from a backend script:
#   import autoload 'tartree/archiveBackend.vim' as AB
#   export class Zip implements AB.ArchiveBackend
#     ...
#   endclass
#
# Usage: from a caller detect a type and get the matching backend
#   import autoload 'tartree/archiveBackend.vim' as AB
#   import autoload 'tartree/archiveRegistry.vim' as Registry
#   var archiveType = AB.ArchiveTypeDetect(path)
#   var backend: AB.ArchiveBackend = Registry.NewBackend(archiveType)
#######################################################################
export interface ArchiveBackend
  # Returns the compression kind for `archive`: 'gzip', 'bzip2',
  # 'bzip3', 'xz', 'lzma', 'zstd', 'lz4', or '' for none/unrecognised.
  def DetectCompression(archive: string): string

  # Returns the ambiguous "container" suffix (e.g. '.tgz') if `archive`
  # ends in one of those shorthand extensions, else ''.
  def ContainerSuffix(archive: string): string

  # Builds the shell pipeline that decompresses `archive` (if needed)
  # and extracts `member` into the current directory, for use with
  # `:r!`. `memberDecmp` is an extra pipe stage (e.g. '|bzcat')
  def ExtractCmd(archive: string, member: string, memberDecmp: string): string

  # Decompresses `archive` on disk in place. Returns
  # {path, kind, container, ok}: `path` is the (possibly renamed) file
  # to now work with, `kind`/`container` are handed back to Recompress().
  def Decompress(archive: string): dict<any>

  # Recompresses `path` (as produced by Decompress) back using `kind`,
  # restoring `container`'s shorthand extension if there was one.
  # Returns {path, ok}.
  def Recompress(path: string, kind: string, container: string): dict<any>

  # Removes `member` from the (uncompressed) `archive`. 
  def DeleteMember(archive: string, member: string): number

  # Adds/updates `member` in the (uncompressed) `archive`.
  def AddMember(archive: string, member: string): number

  # Lists the member paths contained in `archive`
  def List(archive: string): list<string>
endinterface

#######################################################################
# Method: ArchiveTypeDetect
# Extension is checked first. Magic-byte sniffing is the fallback for
# extensionless or renamed files.
#
# Caveats:
#   - Pre-POSIX / old V7 tar archives have no reliable magic bytes at
#     all; they can only be recognised by extension.
#   - Plain LZMA (.lzma) is extension-only
#   - Old binary-format cpio isn't checked.
#   - A renamed tar file with no `.tar.*`/`.tgz`-style extension is 
#       alwaysreported as the bare compressor type.
#######################################################################
export def ArchiveTypeDetect(archivePath: string): string
  var lowerPath: string = tolower(archivePath)

  # ---- Extension checks ---------------------------------------------
  # Anything that looks like a tar wrapped in a compressor wins first
  if lowerPath =~# '\.tar\.\a\+$'
      || lowerPath =~# '\.t\%(gz\|bz2\=\|xz\|zst\|lz4\)$'
      || lowerPath =~# '\.ta[zZ]$'
    return 'tar'
  endif
  if lowerPath =~# '\.tar$'
    return 'tar'
  endif

  var extKind: dict<string> = {
      '\.zip$': 'zip', '\.jar$': 'zip', '\.war$': 'zip', '\.apk$': 'zip',
      '\.7z$': '7z',
      '\.rar$': 'rar',
      '\.gz$': 'gzip',
      '\.bz2$': 'bzip2',
      '\.bz3$': 'bzip3',
      '\.xz$': 'xz',
      '\.lzma$': 'lzma',
      '\.zst$': 'zstd',
      '\.lz4$': 'lz4',
      '\.cab$': 'cab',
      '\.a$': 'ar', '\.deb$': 'ar',
      '\.cpio$': 'cpio',
      }
  for [pat, kind] in items(extKind)
    if lowerPath =~# pat
      return kind
    endif
  endfor

  # ----- Magic-byte sniff (extensionless or renamed files) -----------
  if !filereadable(archivePath)
    return 'unknown'
  endif
  var header = readblob(archivePath, 0, 8)

  if len(header) >= 4 && (header[0 : 3] == 0z504B0304
      || header[0 : 3] == 0z504B0506 || header[0 : 3] == 0z504B0708)
    return 'zip'
  elseif len(header) >= 6 && header[0 : 5] == 0z377ABCAF271C
    return '7z'
  elseif len(header) >= 6 && header[0 : 5] == 0z526172211A07
    return 'rar'                                    # covers v1.5-4.x and v5
  elseif len(header) >= 3 && header[0 : 2] == 0z425A68
    return 'bzip2'
  elseif len(header) >= 3 && header[0 : 2] == 0z425A33
    return 'bzip3'
  elseif len(header) >= 6 && header[0 : 5] == 0zFD377A585A00
    return 'xz'
  elseif len(header) >= 4 && header[0 : 3] == 0z28B52FFD
    return 'zstd'
  elseif len(header) >= 4 && header[0 : 3] == 0z04224D18
    return 'lz4'
  elseif len(header) >= 2 && (header[0 : 1] == 0z1F8B || header[0 : 1] == 0z1F9D
      || header[0 : 1] == 0z1F9E || header[0 : 1] == 0z1FA0
      || header[0 : 1] == 0z1F1E)
    return 'gzip'
  elseif len(header) >= 4 && header[0 : 3] == 0z4D534346
    return 'cab'
  elseif len(header) >= 8 && header[0 : 7] == 0z213C617263683E0A
    return 'ar'                                     # also matches .deb
  elseif len(header) >= 6 && (header[0 : 5] == 0z303730373031
      || header[0 : 5] == 0z303730373037)
    return 'cpio'                                   # newc / odc ASCII headers
  endif

  # ustar tar files carry their magic at offset 257, not at byte 0.
  if getfsize(archivePath) > 262
    if readblob(archivePath, 257, 5) == 0z7573746172
      return 'tar'
    endif
  endif

  return 'unknown'
enddef
