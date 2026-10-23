# TODO

- Two threads on one line: only the last is shown and can be replied to.

- If discarding the old draft works and drafting the new one fails, the
  reply keeps the discarded id and every later `:write` fails.

- Empty comment text breaks the summary and the reply's status line.

- `:MemexReply` on a `:MemexDrafts` entry says "no thread here".

- `:MemexRetest` with several `ci` bindings: memex gives stdin only to a
  single adapter, so the reason doesn't reach them.

- A sent comment stays in its buffer: writing it again sends it again,
  after asking.

- `:MemexTests` lists every test; a suite of thousands buries the few
  failures under passes.
