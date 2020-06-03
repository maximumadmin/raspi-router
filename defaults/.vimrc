" allow to use arrows
set nocompatible

" allow to use backspace
set backspace=2

" disable annoying mouse support
set mouse=
set ttymouse=

" allow to jump words with ctrl+arrows
set term=xterm

" enable syntax highlighting
filetype plugin on
syntax on

" disable comment continuation (it breaks copying and pasting if enabled)
autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o

" disable creation of .viminfo file as it does not work on read-only filesystems
set viminfo=
