# vim-memex

Review threads of a change in Vim, from [memex], and replies to them.

    :MemexThreads [CHANGE]   open threads of CHANGE, or of HEAD's change,
                             in the quickfix list and after their lines
    :MemexThreads! [CHANGE]  resolved ones too
    :MemexReply              reply to the thread at the cursor or quickfix
                             entry; :write saves it as a draft
    :MemexDrafts             your drafts in the quickfix list
    :MemexPublish            publish your drafts, after asking

Needs `memex` with a `discussion` binding, and `jq`.

Tests run offline, in Vims of their own under tmux: `test/run [TEST...]`.

[memex]: https://github.com/roolebo/memex
