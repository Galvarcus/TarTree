vim9script

if exists('s:is_loaded')
  finish
endif
var is_loaded: bool = true

# Logger
import 'Logger/logger.vim' as Log
var log = Log.Logger.new('TarTree', expand('<sfile>:t'))

#######################################################################
# archiveRegistry.vim - to avoid circular imports via archiveBackend.vim
# 
#######################################################################

# Import any implemented backends
import autoload 'tartree/archiveBackend.vim' as AB
import autoload 'tartree/tarBackend.vim' as TB
# import autoload 'tartree/zipBackend.vim' as ZB    # add as implemented
# import autoload 'tartree/gzipBackend.vim' as GzB  # add as implemented



# Returns fresh backend for `archiveType` (AB.ArchiveTypeDetect() returntype). 
export def NewBackend(archiveType: string): AB.ArchiveBackend
  if archiveType ==# 'tar'
    return TB.GnuTar.new()
  endif
  # elseif archiveType ==# 'zip'
  #   return ZB.Zip.new()
  # elseif archiveType ==# 'gzip'
  #   return GzB.Gzip.new()
  
  throw log.Fmt('No backend registered for archive type: ' .. archiveType)
enddef

