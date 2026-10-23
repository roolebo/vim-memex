# TODO

- Two threads on one line: only the last is shown and can be replied to.

- If discarding the old draft works and drafting the new one fails, the
  reply keeps the discarded id and every later `:write` fails.

- `:Memex discussion draft` on a draft replies to the draft instead of
  editing it.

- `:Memex discussion drafts` shows only the drafts after lines; the
  other threads go until the next `:Memex review`.

- `:Memex ci retest` with several `ci` bindings: memex gives stdin only
  to a single adapter, so the reason doesn't reach them.

- A sent comment stays in its buffer: writing it again sends it again,
  after asking.

- `:Memex ci tests` lists every test; a suite of thousands buries the
  few failures under passes.

- Completion lists memex's commands as the plugin knows them; a command
  memex gains completes only once added there.
