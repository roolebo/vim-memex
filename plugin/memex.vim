" vim-memex - review threads, issues, CI and history from memex in Vim
" Maintainer:	Roman Bolshakov <roman@subtile.systems>
" License: MIT

vim9script

if exists("g:loaded_memex")
  finish
endif
g:loaded_memex = 1

# Text after a line
if !has('patch-9.0.0121')
  echohl WarningMsg
  echomsg 'vim-memex: needs Vim 9.0.0121 or later'
  echohl None
  finish
endif

import autoload 'memex.vim'

command -bang -nargs=+ -complete=customlist,memex#Complete Memex
  \ memex.Memex(<bang>0, <f-args>)

nnoremap <Plug>(memex-show) <ScriptCmd>memex.Popup()<CR>
if exists('g:memex_map')
  execute $'nmap {g:memex_map} <Plug>(memex-show)'
endif

augroup memex
  autocmd!
  autocmd BufWinEnter * memex.Mark(str2nr(expand('<abuf>')))
augroup END
