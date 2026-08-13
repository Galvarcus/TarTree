vim9script

g:tartree_win_width = get(g:, 'tartree_win_width', 31)
g:tartree_show_hidden = get(g:, 'tartree_show_hidden', 0)
g:tartree_arrow_open = get(g:, 'tartree_arrow_open', '▾ ')
g:tartree_arrow_closed = get(g:, 'tartree_arrow_closed', '▸ ')
g:tartree_auto_open = get(g:, 'tartree_auto_open', 0)


g:tartree_tar_browseoptions = get(g:, 'tartree_tar_browseoptions', 'tf')
g:tartree_tar_readoptions = get(g:, 'tartree_tar_readoptions', 'pxf')
g:tartree_tar_cmd = get(g:, 'tartree_tar_cmd', 'tar')
g:tartree_tar_writeoptions = get(g:, 'tartree_tar_writeoptions', 'uf')
# Note: --delete not supported on BSD
g:tartree_tar_delfile = get(g:, 'tartree_tar_delfile', '--delete -f')


g:tar_secure = ' -- '
g:tar_leading_pat = '\m^\%([.]\{,2\}/\)\+'

