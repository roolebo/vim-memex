" vim-memex - review threads, issues, CI and versions from memex in Vim
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

command -bang -nargs=? MemexThreads memex.Threads(<bang>0, <q-args>)
command MemexReply memex.Reply()
command MemexDrafts memex.Drafts()
command MemexPublish memex.Publish()

command -nargs=? MemexIssue memex.Issue(<q-args>)
command -nargs=1 MemexIssues memex.Issues(<q-args>)
command -nargs=1 MemexComment memex.Comment(<q-args>)
command -nargs=+ MemexTransition memex.Transition(<f-args>)

command -nargs=? MemexRuns memex.Runs(<q-args>)
command MemexSuites memex.Suites()
command MemexTests memex.Tests()
command MemexLogs memex.Logs()
command MemexRetest memex.Retest()

augroup memex
  autocmd!
  autocmd BufWinEnter * memex.Mark(str2nr(expand('<abuf>')))
augroup END
