vim9script
# Review threads of the change at HEAD, from `memex discussion`, in the
# quickfix list and after the lines they are about.

const PROP = 'memex_thread'

# Text shown after a line, by file and line
var marks: dict<dict<string>> = {}

def Warn(message: string)
  echohl WarningMsg
  echomsg $'vim-memex: {message}'
  echohl None
enddef

# Prints the change RECORD, then its thread RECORDs
const SCRIPT = 'change=$(memex discussion locate "$(git rev-parse HEAD)")'
  .. ' || exit 1; printf "%s\n" "$change";'
  .. ' memex discussion threads "$(printf "%s" "$change" | jq -r .id)"'

export def Threads(all: bool)
  var dir = expand('%:p:h')
  if !isdirectory(dir)
    dir = getcwd()
  endif
  var git = $'git -C {shellescape(dir)}'
  var root = trim(system($'{git} rev-parse --show-toplevel'))
  if v:shell_error != 0
    Warn($'not in a git working copy: {dir}')
    return
  endif
  # Raw: a RECORD can be longer than what Vim passes as one line. The
  # job may exit before its output is read, so wait for both.
  var job = {out: '', err: '', status: -1, closed: false}
  var Finish = () => {
    if job.closed && job.status >= 0
      Show(root, split(job.out, "\n"), split(job.err, "\n"),
        job.status, all)
    endif
  }
  job_start(['sh', '-c', SCRIPT], {
    cwd: root,
    out_mode: 'raw',
    err_mode: 'raw',
    out_cb: (_, chunk) => {
      job.out ..= chunk
    },
    err_cb: (_, chunk) => {
      job.err ..= chunk
    },
    close_cb: (_) => {
      job.closed = true
      Finish()
    },
    exit_cb: (_, status) => {
      job.status = status
      Finish()
    },
  })
  echo 'vim-memex: reading threads...'
enddef

def Summary(thread: dict<any>, current: string): string
  var comments = thread.data.comments
  var first = comments[0]
  var text = $'{first.author.name}: {split(first.text, "\n")[0]}'
  if len(comments) > 1
    text ..= $' (+{len(comments) - 1})'
  endif
  if thread.data.resolved == true
    text ..= ' [resolved]'
  endif
  if thread.data.revision != current
    text ..= $' [patch set {thread.data.revision}]'
  endif
  return text
enddef

def Item(root: string, thread: dict<any>, current: string): dict<any>
  var anchor = thread.data.anchor
  var item = {text: Summary(thread, current), user_data: thread.id}
  if anchor.on == 'lines'
    item.filename = $'{root}/{anchor.path}'
    item.lnum = anchor.start
    item.end_lnum = anchor.end
    if anchor.side == 'base'
      item.text = $'[base] {item.text}'
    endif
  elseif anchor.on == 'file'
    item.filename = $'{root}/{anchor.path}'
    item.lnum = 1
  elseif anchor.on == 'message'
    item.text = $'[commit message] {item.text}'
  else
    item.text = $'[change] {item.text}'
  endif
  return item
enddef

def Show(root: string, out: list<string>, err: list<string>,
    status: number, all: bool)
  if status != 0
    Warn(empty(err) ? $'memex exited with {status}' : join(err, ' '))
    return
  endif
  var records = out->mapnew((_, line) => json_decode(line))
  var change = records[0]
  var threads = records[1 :]
  if !all
    threads = threads->filter((_, t) => t.data.resolved != true)
  endif
  var items = threads->mapnew((_, t) => Item(root, t, change.data.current))
  setqflist([], ' ', {title: $'memex: {change.data.title}', items: items})

  marks = {}
  for item in items
    if has_key(item, 'filename') && item.text !~ '^\[base\]'
      if !has_key(marks, item.filename)
        marks[item.filename] = {}
      endif
      marks[item.filename][item.lnum] = item.text
    endif
  endfor
  for buf in getbufinfo({bufloaded: true})
    Mark(buf.bufnr)
  endfor
  echo $'vim-memex: {len(items)} threads on change {change.id}'
enddef

# Shows the threads of the buffer's file after their lines
export def Mark(buf: number)
  if empty(prop_type_get(PROP))
    highlight default link MemexThread Comment
    prop_type_add(PROP, {highlight: 'MemexThread'})
  endif
  if !bufloaded(buf)
    return
  endif
  prop_remove({type: PROP, bufnr: buf, all: true})
  var file = fnamemodify(bufname(buf), ':p')
  var last = getbufinfo(buf)[0].linecount
  for [lnum, text] in items(get(marks, file, {}))
    if str2nr(lnum) <= last
      prop_add(str2nr(lnum), 0, {type: PROP, bufnr: buf,
        text: $'  {text}', text_align: 'after'})
    endif
  endfor
enddef
