vim9script

import autoload 'tartree.vim' as T

command! -nargs=? -complete=file TarTree T.Open(<f-args>)
command! -nargs=0 TarTreeToggle T.Toggle()
command! -nargs=0 TarTreeClose T.Close()
