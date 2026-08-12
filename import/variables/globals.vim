vim9script

g:tartree_win_width = get(g:, 'tartree_win_width', 31)
g:tartree_show_hidden = get(g:, 'tartree_show_hidden', 0)
g:tartree_arrow_open = get(g:, 'tartree_arrow_open', '▾ ')
g:tartree_arrow_closed = get(g:, 'tartree_arrow_closed', '▸ ')
g:tartree_auto_open = get(g:, 'tartree_auto_open', 1)


g:tar_browseoptions = get(g:, 'tar_browseoptions', 'tf')
g:tar_readoptions = get(g:, 'tar_readoptions', 'pxf')
g:tar_cmd = get(g:, 'tar_cmd', 'tar')
g:tar_writeoptions = get(g:, 'tar_writeoptions', 'uf')
# Note: --delete not supported on BSD
g:tar_delfile = get(g:, 'tar_delfile', '--delete -f')
g:tar_extractcmd = get(g:, 'tar_extractcmd', 'tar -pxf')

g:netrw_cygwin = get(g:, 'netrw_cygwin',
    (has('win32') || has('win95') || has('win64') || has('win16'))
    && &shell =~ '\%(\<bash\>\|\<zsh\>\)\%(\.exe\)\=$' ? 1 : 0)
g:tar_shq = get(g:, 'tar_shq',
    (exists('+shq') && &shq != '') ? &shq
    : (has('win32') || has('win95') || has('win64') || has('win16')) ? (g:netrw_cygwin ? "'" : '"')
    : "'")

if !exists('g:tar_copycmd')
  if !exists('g:netrw_localcopycmd')
    if has('win32') || has('win95') || has('win64') || has('win16')
      g:netrw_localcopycmd = g:netrw_cygwin ? 'cp' : 'copy'
    elseif has('unix') || has('macunix')
      g:netrw_localcopycmd = 'cp'
    else
      g:netrw_localcopycmd = ''
    endif
  endif
  g:tar_copycmd = g:netrw_localcopycmd
endif


g:tar_secure = ' -- '
g:tar_leading_pat = '\m^\%([.]\{,2\}/\)\+'

