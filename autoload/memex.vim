vim9script
# :Memex runs memex and shows its RECORDs by their kind: in the quickfix
# list, in buffers of their own, and review threads also after the lines
# they are about. Commands that write ask first.

const PROP = 'memex_thread'

# The change shown last, {} if unknown, its working copy and its threads
# by id
var shown: dict<any> = {}
# Text and thread id shown after a line, by file and line
var marks: dict<dict<dict<string>>> = {}

# What :Memex completes: memex's commands and roles, then each role's
# commands, as its specification lists them
const COMMANDS = {
  '': ['bindings', 'ci', 'code', 'discussion', 'history', 'review', 'show',
    'tracker'],
  discussion: ['capabilities', 'change', 'discard', 'draft', 'drafts',
    'locate', 'publish', 'series', 'threads'],
  tracker: ['capabilities', 'comment', 'issue', 'search', 'transition'],
  ci: ['capabilities', 'logs', 'retest', 'run', 'runs', 'suites', 'tests'],
  code: ['base', 'capabilities', 'commits', 'compare', 'diff', 'fetch',
    'versions', 'workspaces'],
}

# What a command takes from the cursor when its argument is missing: the
# change of the RECORD there, or the id of a RECORD of these kinds
const MISSING = {
  history: 'change',
  'discussion change': 'change',
  'discussion series': 'change',
  'discussion threads': 'change',
  'discussion drafts': 'change',
  'discussion publish': 'change',
  'ci run': 'run',
  'ci suites': 'run',
  'ci retest': 'run',
  'ci tests': 'suite',
  'ci logs': 'run suite test',
  'tracker issue': 'issue',
  'tracker comment': 'issue',
}

const FAILED = ['fail', 'timeout', 'error']

def Warn(message: string)
  echohl WarningMsg
  echomsg $'vim-memex: {message}'
  echohl None
enddef

export def Complete(lead: string, line: string, pos: number): list<string>
  # The words before the one completed, without the command's name
  var words = split(strpart(line, 0, pos))[1 :]
  if !empty(lead)
    words = words[: -2]
  endif
  var key = empty(words) ? '' : len(words) == 1 ? words[0] : '-'
  return get(COMMANDS, key, [])->copy()
    ->filter((_, c) => stridx(c, lead) == 0)
enddef

# Runs memex WORDS; takes a missing argument from the cursor, and shows
# what memex prints. ALL: resolved threads too.
export def Memex(all: bool, ...words: list<string>)
  var name = join(words[: 1])
  if words[0] == 'show'
    Popup()
  elseif name == 'discussion draft'
    Reply()
  elseif name == 'discussion publish'
    Publish(words)
  elseif name == 'discussion discard'
    Discard(words)
  elseif name == 'tracker comment'
    Comment(words)
  elseif name == 'tracker transition'
    Transition(words)
  elseif name == 'tracker search'
    Search(words)
  elseif name == 'ci retest'
    Retest(words)
  else
    var target = Target(words)
    if !empty(target)
      Query(target.root, target.words, '', join(target.words), all)
    endif
  endif
enddef

# The working copy of the buffer, of the quickfix list in its window, of
# the current file, or of the current directory; warns and returns ''
# outside one
def Root(): string
  if exists('b:memex_root')
    return b:memex_root
  endif
  if &buftype == 'quickfix'
    var context = getqflist({context: 0}).context
    if type(context) == v:t_dict
      return context.root
    endif
  endif
  var dir = expand('%:p:h')
  if !isdirectory(dir)
    dir = getcwd()
  endif
  var git = $'git -C {shellescape(dir)}'
  var root = trim(system($'{git} rev-parse --show-toplevel'))
  if v:shell_error != 0
    Warn('not in a git working copy')
    return ''
  endif
  return root
enddef

# The RECORD at the cursor and its working copy, {root: ROOT, record:
# RECORD}, or {}: the quickfix entry at the cursor in its window, the
# buffer's RECORD, or the thread after the cursor's line
def Under(): dict<any>
  if &buftype == 'quickfix'
    return EntryData(line('.'))
  endif
  if exists('b:memex_record')
    return {root: b:memex_root, record: b:memex_record}
  endif
  var mark = get(get(marks, expand('%:p'), {}), string(line('.')), {})
  return empty(mark) ? {}
    : {root: shown.root, record: shown.threads[mark.id]}
enddef

# What the quickfix entry IDX keeps, as List and ShowThreads keep it, or {}
def EntryData(idx: number): dict<any>
  var data = get(get(getqflist(), idx - 1, {}), 'user_data', '')
  return type(data) == v:t_dict ? data : {}
enddef

# As Under, if its RECORD is of one of KINDS; else, outside the quickfix
# window, the current entry's, if of one of KINDS; else {}
def At(kinds: list<string>): dict<any>
  var Fits = (here) => !empty(here) && index(kinds, here.record.kind) >= 0
  var here = Under()
  if !Fits(here) && &buftype != 'quickfix'
    here = EntryData(getqflist({idx: 0}).idx)
  endif
  return Fits(here) ? here : {}
enddef

# The value of RECORD's first link of type TYPE, or ''
def Link(record: dict<any>, type: string): string
  var links = record.links->copy()->filter((_, l) => l[0] == type)
  return empty(links) ? '' : links[0][1]
enddef

# Where to run memex WORDS, and WORDS with their missing argument from
# the cursor, as MISSING says: {root: ROOT, words: WORDS}; or {} after a
# warning
def Target(words: list<string>): dict<any>
  var name = words[0] == 'history' ? 'history' : join(words[: 1])
  if len(words) > len(split(name)) || !has_key(MISSING, name)
    var root = Root()
    return empty(root) ? {} : {root: root, words: words}
  endif
  if MISSING[name] != 'change'
    var kinds = split(MISSING[name])
    var here = At(kinds)
    if empty(here)
      Warn($'no {join(kinds, " or ")} here; give its id')
      return {}
    endif
    return {root: here.root, words: words + [here.record.id]}
  endif
  var here = Under()
  var change = empty(here) ? '' : Link(here.record, 'change')
  if !empty(change)
    return {root: here.root, words: words + [change]}
  endif
  # memex's own default: HEAD's change
  if name == 'history'
    var root = Root()
    return empty(root) ? {} : {root: root, words: words}
  endif
  if empty(get(shown, 'change', {}))
    Warn('no change here; give one or run :Memex review')
    return {}
  endif
  return {root: shown.root, words: words + [shown.change.id]}
enddef

# Runs the command ARGV in ROOT, writes INPUT to it, and calls Done with
# its exit status and its output
highlight default link MemexBusy PmenuSel

def Spawn(root: string, argv: list<string>, input: string,
    Done: func(number, string))
  # Raw: a RECORD can be longer than what Vim passes as one line. The
  # job may exit before its output is read, so wait for both.
  var job = {out: '', err: '', status: -1, closed: false}
  # While it runs, a note at the top right says so
  var note = popup_create($' {join(argv)}... ', {
    line: 1, col: &columns, pos: 'topright', zindex: 300,
    highlight: 'MemexBusy'})
  var Finish = () => {
    if !job.closed || job.status < 0
      return
    endif
    popup_close(note)
    var err = trim(job.err)
    if job.status == 2
      Warn('not supported by the bound adapter'
        .. (empty(err) ? '' : $': {err}'))
    elseif job.status != 0
      Warn(empty(err) ? $'memex exited with {job.status}' : err)
    endif
    Done(job.status, job.out)
  }
  var j = job_start(argv, {
    cwd: root,
    in_mode: 'raw',
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
  var channel = job_getchannel(j)
  if !empty(input)
    ch_sendraw(channel, input)
  endif
  ch_close_in(channel)
enddef

# Runs memex WORDS in ROOT with INPUT and shows its output as memex
# TITLE; ALL: resolved threads too
def Query(root: string, words: list<string>, input: string, title: string,
    all: bool)
  Spawn(root, ['memex'] + words, input, (status, out) => {
    if status == 0
      Render(root, $'memex {title}', out, all)
    endif
  })
  echo $'vim-memex: memex {title}...'
enddef

# Asks QUESTION, then runs memex WORDS in ROOT with INPUT and calls Done
# if it succeeds
def Write(root: string, words: list<string>, input: string,
    question: string, Done: func())
  if confirm(question, "&Yes\n&No", 2) != 1
    return
  endif
  Spawn(root, ['memex'] + words, input, (status, _) => {
    if status == 0
      Done()
    endif
  })
enddef

# The RECORD a line of output holds, or {}
def Record(line: string): dict<any>
  try
    var record = json_decode(line)
    return type(record) == v:t_dict && has_key(record, 'kind') ? record : {}
  catch
    return {}
  endtry
enddef

# Shows OUT, memex's output in ROOT, under TITLE: threads after their
# lines and in the quickfix list, a single issue in its buffer, other
# RECORDs in the quickfix list, and output other than RECORDs in a buffer
def Render(root: string, title: string, out: string, all: bool)
  var lines = split(out, "\n")
  var records = lines->mapnew((_, l) => Record(l))
  if index(records, {}) >= 0
    Scratch(root, $'memex://{split(title)[1 :]->join("/")}', lines)
    return
  endif
  var threads = records->copy()->filter((_, r) => r.kind == 'thread')
  if !empty(threads)
    var change = records->copy()->filter((_, r) => r.kind == 'change')
      ->get(0, {})
    # Drafts come without their change
    var last = get(shown, 'change', {})
    if empty(change) && !empty(last)
        && last.id == Link(threads[0], 'change')
      change = last
    endif
    ShowThreads(root, title, change, threads, all)
  elseif len(records) == 1 && records[0].kind == 'issue'
    ShowIssue(root, records[0])
  else
    List(root, title, records)
  endif
enddef

# Lists RECORDs of ROOT in a new quickfix list TITLE, failed tests first.
# Each entry keeps its RECORD and ROOT for the commands that act on it.
def List(root: string, title: string, records: list<dict<any>>)
  # sort() keeps the order within each
  var Passed = (r) => r.kind == 'test' && index(FAILED, r.data.result) < 0
    ? 1 : 0
  var items = records->copy()->sort((a, b) => Passed(a) - Passed(b))
    ->mapnew((_, r) => Item(root, r)
      ->extend({user_data: {root: root, record: r}}))
  setqflist([], ' ', {title: title, items: items, context: {root: root}})
  var kinds = records->mapnew((_, r) => r.kind)->sort()->uniq()
  echo $'vim-memex: {len(items)} '
    .. (len(kinds) == 1 ? $'{kinds[0]}s' : 'records')
enddef

# The first line of TEXT, cut to WIDTH characters
def Short(text: string, width: number): string
  var line = get(split(text, "\n"), 0, '')
  return strchars(line) <= width ? line
    : strcharpart(line, 0, width - 1) .. '…'
enddef

# The quickfix entry of RECORD, from ROOT
def Item(root: string, record: dict<any>): dict<any>
  var data = record.data
  if record.kind == 'run'
    var config = data.config
    var words = [data.result ?? data.status,
      keys(config)->sort()->mapnew((_, k) => config[k])->join('/'),
      data.started ?? '']
    return {text: words->filter((_, w) => !empty(w))->join(' ')}
  elseif record.kind == 'suite'
    var counts = data.counts
    var text = $'{data.result} {data.name}'
    if !empty(counts)
      text ..= ' (' .. keys(counts)->sort()
        ->mapnew((_, r) => $'{counts[r]} {r}')->join(', ') .. ')'
    endif
    return {text: text}
  elseif record.kind == 'test'
    var text = $'{data.result} {data.name}'
    if !empty(data.error)
      text ..= $': {Short(data.error, 60)}'
    endif
    return {text: text}
  elseif record.kind == 'log'
    # The URL as the text, for gx to open
    return {text: $'{data.name}: {data.url}'}
  elseif record.kind == 'issue'
    return {text: $'{record.id} {data.status}: {Short(data.title, 60)}'}
  elseif record.kind == 'version'
    var text = (data.revision == null ? 'local' : $'PS{data.revision}')
      .. $' {data.commit[: 11]}'
    if data.current
      text ..= ' current'
    endif
    var places = data.where->copy()->filter((_, w) => w != 'server')
    if !empty(places)
      text ..= $' [{places->join(", ")}]'
    endif
    return {text: text}
  elseif record.kind == 'workspace'
    var text = $'{data.branch ?? "(detached)"} {data.head[: 11]}'
    if data.changed == true
      text ..= ' [changed]'
    endif
    return {filename: data.path, text: text}
  elseif record.kind == 'commit'
    return {text: $'{data.commit[: 11]} {Short(data.subject, 60)}'}
  elseif record.kind == 'file'
    return {filename: $'{root}/{data.path}', lnum: 1, text: data.status}
  endif
  var about = ['title', 'subject', 'name', 'status']
    ->mapnew((_, k) => get(data, k, null))
    ->filter((_, v) => type(v) == v:t_string && !empty(v))
  return {text: $'{record.kind} {record.id}'
    .. (empty(about) ? '' : $': {Short(about[0], 60)}')}
enddef

# Shows LINES in the read-only buffer NAME of ROOT, in its window or a
# new one
def Scratch(root: string, name: string, lines: list<string>)
  var win = bufwinid(name)
  if win > 0
    win_gotoid(win)
  else
    execute $'new {fnameescape(name)}'
  endif
  setlocal buftype=nofile bufhidden=wipe noswapfile modifiable
  silent :%delete _
  setline(1, lines)
  setlocal nomodifiable
  b:memex_root = root
enddef

def ShowIssue(root: string, issue: dict<any>)
  var data = issue.data
  var lines = [$'# {issue.id}: {data.title}', '',
    $'- status: {data.status}',
    $'- assignee: {(data.assignee ?? {name: "nobody"}).name}',
    $'- url: {data.url}', '']
    + split(trim(data.text, "\n"), "\n", true)
  for comment in data.comments
    lines += ['', $'## {comment.author.name}, {comment.created}', '']
      + split(trim(comment.text, "\n"), "\n", true)
  endfor
  Scratch(root, $'memex://issue/{issue.id}', lines)
  setlocal filetype=markdown
  b:memex_record = issue
enddef

def Summary(thread: dict<any>, current: string): string
  var comments = thread.data.comments
  var first = comments[0]
  var text = $'{first.author.name}: {Short(first.text, 60)}'
  if len(comments) > 1
    text ..= $' (+{len(comments) - 1})'
  endif
  if thread.data.resolved == true
    text ..= ' [resolved]'
  endif
  if !empty(current) && thread.data.revision != current
    text ..= $' [patch set {thread.data.revision}]'
  endif
  if comments[-1].draft == true
    text = $'[draft] {text}'
  endif
  return text
enddef

def ThreadItem(root: string, thread: dict<any>, current: string): dict<any>
  var anchor = thread.data.anchor
  var item = {text: Summary(thread, current),
    user_data: {root: root, record: thread}}
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

# Lists THREADS of CHANGE, {} if unknown, from ROOT in a new quickfix
# list TITLE, and shows them after their lines; resolved ones only if ALL
def ShowThreads(root: string, title: string, change: dict<any>,
    threads: list<dict<any>>, all: bool)
  shown = {root: root, change: change, threads: {}}
  for t in threads
    shown.threads[t.id] = t
  endfor
  var current = empty(change) ? '' : change.data.current
  var items = threads->copy()
    ->filter((_, t) => all || t.data.resolved != true)
    ->mapnew((_, t) => ThreadItem(root, t, current))
  setqflist([], ' ', {title: title, items: items, context: {root: root}})

  marks = {}
  for item in items
    if has_key(item, 'filename') && item.text !~ '^\[base\]'
      if !has_key(marks, item.filename)
        marks[item.filename] = {}
      endif
      marks[item.filename][item.lnum] = {text: item.text,
        id: item.user_data.record.id}
    endif
  endfor
  for buf in getbufinfo({bufloaded: true})
    Mark(buf.bufnr)
  endfor
  echo $'vim-memex: {len(items)} threads'
    .. (empty(change) ? '' : $' on change {change.id}')
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
  for [lnum, mark] in items(get(marks, file, {}))
    if str2nr(lnum) <= last
      prop_add(str2nr(lnum), 0, {type: PROP, bufnr: buf,
        text: $'  {mark.text}', text_align: 'after'})
    endif
  endfor
enddef

# The thread at the cursor as Under gives it, or {} after a warning
def Thread(): dict<any>
  var here = Under()
  if empty(here) || here.record.kind != 'thread'
    Warn('no thread here; run :Memex review first')
    return {}
  endif
  return here
enddef

# Shows the whole thread at the cursor in a popup that closes when the
# cursor leaves the line, or on <Esc> or q
export def Popup()
  var here = Thread()
  if empty(here)
    return
  endif
  var thread = here.record
  var lines = []
  for c in thread.data.comments
    if !empty(lines)
      add(lines, '')
    endif
    var head = c.author.name
    if c.draft == true
      head ..= ' (draft)'
    endif
    add(lines, $'{head}, patch set {c.revision}:')
    lines += split(c.text, "\n", true)->mapnew((_, l) => $'  {l}')
  endfor
  if thread.data.resolved == true
    lines += ['', '[resolved]']
  endif
  popup_atcursor(lines, {
    maxwidth: min([78, winwidth(0) - 4]),
    maxheight: &lines / 2,
    wrap: true,
    border: [],
    padding: [0, 1, 0, 1],
    # Open while the cursor moves along the line, to read it
    moved: [line('.'), 1, v:maxcol],
    scrollbar: true,
    filter: (id, key) => {
      if key != "\<Esc>" && key != 'q'
        return false
      endif
      popup_close(id)
      return true
    },
  })
enddef

# Drafts the reply on stdin; the reply's earlier draft, if any, goes
const DRAFT = '[ -z "$2" ] || memex discussion discard "$1" "$2"'
  .. ' && memex discussion draft "$1"'

# Opens a reply to the thread at the cursor; :write drafts it
def Reply()
  var here = Thread()
  if empty(here)
    return
  endif
  var thread = here.record
  var last = thread.data.comments[-1]
  execute $'new memex://reply/{thread.id}'
  # Open already: keep the draft it saved
  if exists('b:memex_reply')
    return
  endif
  setlocal buftype=acwrite bufhidden=wipe noswapfile filetype=markdown
  b:memex_root = here.root
  b:memex_reply = {change: Link(thread, 'change'), to: last.id, draft: ''}
  &l:statusline = $'memex reply to {last.author.name}: '
    .. Short(last.text, 60)
  autocmd BufWriteCmd <buffer> SaveReply()
enddef

def SaveReply()
  var reply = b:memex_reply
  var text = join(getline(1, '$'), "\n")->trim()
  if empty(text)
    Warn('empty reply, nothing drafted')
    return
  endif
  var buf = bufnr()
  var input = json_encode({reply_to: reply.to, text: text})
  Spawn(b:memex_root, ['sh', '-c', DRAFT, 'sh', reply.change, reply.draft],
    input, (status, out) => {
      var record = Record(get(split(out, "\n"), 0, ''))
      if status == 0 && !empty(record)
        reply.draft = record.data.comments[0].id
        setbufvar(buf, '&modified', false)
        echo $'vim-memex: draft saved on change {reply.change}'
      endif
    })
enddef

def Publish(words: list<string>)
  var target = Target(words)
  if empty(target)
    return
  endif
  var change = target.words[2]
  Write(target.root, target.words, '{}',
    $'Publish your drafts on change {change}?', () => {
      echo $'vim-memex: published on change {change}'
    })
enddef

def Discard(words: list<string>)
  var root = Root()
  if !empty(root)
    Write(root, words, '', $'Run memex {join(words)}?', () => {
      echo $'vim-memex: done: memex {join(words)}'
    })
  endif
enddef

# Opens a comment on the issue; :write sends it, after asking
def Comment(words: list<string>)
  var target = Target(words)
  if empty(target)
    return
  endif
  var id = target.words[2]
  execute $'new {fnameescape($"memex://comment/{id}")}'
  # Open already: keep the text written so far
  if exists('b:memex_comment')
    return
  endif
  setlocal buftype=acwrite bufhidden=wipe noswapfile filetype=markdown
  b:memex_root = target.root
  b:memex_comment = id
  &l:statusline = $'memex comment on {id}'
  autocmd BufWriteCmd <buffer> SaveComment()
enddef

def SaveComment()
  var id = b:memex_comment
  var text = join(getline(1, '$'), "\n")->trim()
  if empty(text)
    Warn('empty comment, nothing sent')
    return
  endif
  var buf = bufnr()
  Write(b:memex_root, ['tracker', 'comment', id], text,
    $'Send the comment to issue {id}?', () => {
      setbufvar(buf, '&modified', false)
      echo $'vim-memex: comment sent to issue {id}'
    })
enddef

def Transition(words: list<string>)
  if len(words) < 4
    Warn('give the issue and the status to move it to')
    return
  endif
  var root = Root()
  if empty(root)
    return
  endif
  var id = words[2]
  var status = join(words[3 :])
  Write(root, ['tracker', 'transition', id, status], '',
    $'Move issue {id} to {status}?', () => {
      echo $'vim-memex: issue {id} moved to {status}'
    })
enddef

# The query goes on stdin, in the tracker's own language
def Search(words: list<string>)
  var root = Root()
  if !empty(root)
    Query(root, words[: 1], join(words[2 :]), join(words), false)
  endif
enddef

def Retest(words: list<string>)
  var target = Target(words)
  if empty(target)
    return
  endif
  var id = target.words[2]
  var reason = input($'Why retest run {id}? ')
  if empty(reason)
    Warn('no reason given, nothing retested')
    return
  endif
  Write(target.root, target.words, json_encode({reason: reason}),
    $'Retest run {id}: {reason}?', () => {
      echo $'vim-memex: retest of run {id} asked for'
    })
enddef
