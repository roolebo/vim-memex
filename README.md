# vim-memex

What [memex] has about your working copy, in Vim: review threads of a
change, issues, CI results and versions of a commit.

Results go to the quickfix list. Commands that act on a result take the
quickfix entry at the cursor in the quickfix window, else the current
one.

Review threads, from the `discussion` role:

    :MemexThreads [CHANGE]   open threads of CHANGE, or of HEAD's change,
                             in the quickfix list and after their lines
    :MemexThreads! [CHANGE]  resolved ones too
    :MemexReply              reply to the thread at the cursor or quickfix
                             entry; :write saves it as a draft
    :MemexDrafts             your drafts in the quickfix list
    :MemexPublish            publish your drafts, after asking

Issues, from the `tracker` role:

    :MemexIssue [ISSUE]      show ISSUE, or the issue of the entry
    :MemexIssues QUERY       issues matching QUERY, in the tracker's own
                             search language
    :MemexComment ISSUE      write a comment on ISSUE; :write sends it,
                             after asking
    :MemexTransition ISSUE STATUS
                             move ISSUE to STATUS, after asking

CI results, from the `ci` role:

    :MemexRuns [COMMIT]      runs that tested COMMIT, or HEAD
    :MemexSuites             suites of the run of the entry
    :MemexTests              tests of the suite of the entry, failures
                             first
    :MemexLogs               logs of the run, suite or test of the entry,
                             by URL: gx on it opens it
    :MemexRetest             run the run of the entry again, after asking
                             why

Versions and workspaces, from the `code` role:

    :MemexVersions           versions of a change, and where each is: of
                             the commit of the entry, of the change of the
                             thread at the cursor, or of HEAD
    :MemexWorkspaces         working copies of the repository, with what
                             they have checked out

Needs `memex` with the roles you use bound, and `jq`. When the bound
adapter lacks a command, the command says so.

Tests run offline, in Vims of their own under tmux: `test/run [TEST...]`.

[memex]: https://github.com/roolebo/memex
