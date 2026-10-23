# vim-memex

What [memex] has about your working copy, in Vim: review threads of a
change, issues, CI results and the history of a change.

## Usage

    :Memex[!] ARGS

Runs `memex ARGS` in the background, in the working copy of the current
file; `memex --help` lists what ARGS can be. `<Tab>` completes memex's
commands and roles. `tracker search QUERY` sends QUERY on stdin, as
memex wants it.

What memex prints shows by the kind of its records:

- thread: in the quickfix list and after the line it is about, cut to
  its first line. Resolved threads only with `!`.
- issue: a single one in the read-only buffer `memex://issue/ID`,
  several in the quickfix list.
- any other kind: in the quickfix list, an entry per record. A log's
  entry ends in its URL, for `gx`.
- output other than records, such as `bindings`: in a read-only buffer.

A command that lacks its argument takes it from the record at the
cursor: the quickfix entry at the cursor in the quickfix window, the
issue of an issue's buffer, or the thread after the cursor's line. A
run, suite, test or issue may also be the current quickfix entry.
`history` and `discussion` commands take the change of that record;
without one, `history` takes HEAD's change and `discussion` commands the
change shown last. For example, `:Memex ci suites` on a run lists its
suites.

Commands that write:

- `discussion draft` opens a reply to the thread at the cursor,
  `memex://reply/ID`. `:write` saves it as a draft; a later `:write`
  replaces that draft.
- `tracker comment [ISSUE]` opens a comment on the issue. `:write` sends
  it, after asking.
- `discussion publish`, `discussion discard`, `tracker transition ISSUE
  STATUS` and `ci retest` ask before they run; `ci retest` also asks
  why.

`:Memex show` shows the whole thread at the cursor in a popup. It closes
when the cursor leaves the line, or on `<Esc>` or `q`. The mapping
`<Plug>(memex-show)` does the same; to map a key to it:

    let g:memex_map = 'K'

Needs `memex` with the roles you use bound, and `jq`. When the bound
adapter lacks a command, the command says so.

Tests run offline, in Vims of their own under tmux: `test/run [TEST...]`.

[memex]: https://github.com/roolebo/memex
