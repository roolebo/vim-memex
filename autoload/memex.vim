vim9script
# What memex has about a working copy, in the quickfix list and in
# buffers of their own. Review threads of a change also go after the
# lines they are about, and get replies as drafts.

const PROP = 'memex_thread'

# The change shown last, its working copy and its threads by id
var shown: dict<any> = {}
# Text and thread id shown after a line, by file and line
var marks: dict<dict<dict<string>>> = {}

def Warn(message: string)
  echohl WarningMsg
  echomsg $'vim-memex: {message}'
  echohl None
enddef

# The working copy of the current file, or of the current directory;
# warns and returns '' outside one
def Root(): string
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

# Runs a shell SCRIPT with ARGS in ROOT, writes INPUT to it, and calls
# Done with its exit status and its output RECORDs
def Run(root: string, script: string, args: list<string>, input: string,
    Done: func(number, list<dict<any>>))
  # Raw: a RECORD can be longer than what Vim passes as one line. The
  # job may exit before its output is read, so wait for both.
  var job = {out: '', err: '', status: -1, closed: false}
  var Finish = () => {
    if !job.closed || job.status < 0
      return
    endif
    var err = trim(job.err)
    if job.status == 2
      Warn('not supported by the bound adapter'
        .. (empty(err) ? '' : $': {err}'))
    elseif job.status != 0
      Warn(empty(err) ? $'memex exited with {job.status}' : err)
    endif
    Done(job.status, split(job.out, "\n")->mapnew((_, l) => json_decode(l)))
  }
  var j = job_start(['sh', '-c', script, 'sh'] + args, {
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

# Lists RECORDs in a new quickfix list of NOUN about ABOUT, an entry each
# from ToEntry. Each entry keeps its RECORD and ROOT, the working copy it
# came from, for the commands that act on it.
def List(root: string, noun: string, about: string,
    records: list<dict<any>>, ToEntry: func(dict<any>): dict<any>)
  var items = records->mapnew((_, r) => ToEntry(r)
    ->extend({user_data: {root: root, record: r}}))
  setqflist([], ' ', {title: $'memex {noun}: {about}', items: items})
  echo $'vim-memex: {len(items)} {noun}'
enddef

# Runs SCRIPT as Run does and lists its RECORDs as List does
def Query(root: string, script: string, args: list<string>, input: string,
    noun: string, about: string, ToEntry: func(dict<any>): dict<any>)
  Run(root, script, args, input, (status, records) => {
    if status == 0
      List(root, noun, about, records, ToEntry)
    endif
  })
  echo $'vim-memex: reading {noun}...'
enddef

# The quickfix entry's RECORD and working copy, as List keeps them, if
# the RECORD is of one of KINDS; else {}. The entry is the one at the
# cursor in the quickfix window, else the current one.
def Entry(kinds: list<string>): dict<any>
  var idx = &buftype == 'quickfix' ? line('.') : getqflist({idx: 0}).idx
  var data = get(get(getqflist(), idx - 1, {}), 'user_data', '')
  if type(data) != v:t_dict || index(kinds, data.record.kind) < 0
    return {}
  endif
  return data
enddef

# Shows LINES in the read-only buffer NAME, in its window or a new one
def Scratch(name: string, lines: list<string>)
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
enddef

# Prints the change RECORD of CHANGE, or of HEAD without it, then its
# thread RECORDs
const THREADS = 'if [ -n "$1" ]; then c=$(memex discussion change "$1");'
  .. ' else c=$(memex discussion locate "$(git rev-parse HEAD)"); fi'
  .. ' || exit 1; printf "%s\n" "$c";'
  .. ' memex discussion threads "$(printf "%s" "$c" | jq -r .id)"'

export def Threads(all: bool, change: string)
  var root = Root()
  if empty(root)
    return
  endif
  Run(root, THREADS, [change], '', (status, records) => {
    if status == 0
      Show(root, records[0], records[1 :], all)
    endif
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
  if comments[-1].draft == true
    text = $'[draft] {text}'
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

def Show(root: string, change: dict<any>, threads: list<dict<any>>,
    all: bool)
  shown = {root: root, change: change, threads: {}}
  for t in threads
    shown.threads[t.id] = t
  endfor
  var listed = all ? threads
    : threads->copy()->filter((_, t) => t.data.resolved != true)
  var items = listed->mapnew((_, t) => Item(root, t, change.data.current))
  setqflist([], ' ', {title: $'memex: {change.data.title}', items: items})

  marks = {}
  for item in items
    if has_key(item, 'filename') && item.text !~ '^\[base\]'
      if !has_key(marks, item.filename)
        marks[item.filename] = {}
      endif
      marks[item.filename][item.lnum] = {text: item.text,
        id: item.user_data}
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
  for [lnum, mark] in items(get(marks, file, {}))
    if str2nr(lnum) <= last
      prop_add(str2nr(lnum), 0, {type: PROP, bufnr: buf,
        text: $'  {mark.text}', text_align: 'after'})
    endif
  endfor
enddef

# The thread of the quickfix entry or of the cursor's line, or {}
def Here(): dict<any>
  if empty(shown)
    return {}
  endif
  var id = ''
  if &buftype == 'quickfix'
    var data = get(get(getqflist(), line('.') - 1, {}), 'user_data', '')
    # Entries of other roles keep a dict
    id = type(data) == v:t_string ? data : ''
  else
    var mark = get(get(marks, expand('%:p'), {}), string(line('.')), {})
    id = get(mark, 'id', '')
  endif
  return get(shown.threads, id, {})
enddef

# Drafts the reply on stdin; the reply's earlier draft, if any, goes
const DRAFT = '[ -z "$2" ] || memex discussion discard "$1" "$2"'
  .. ' && memex discussion draft "$1"'

export def Reply()
  var thread = Here()
  if empty(thread)
    Warn('no thread here; run :MemexThreads first')
    return
  endif
  var reply = {root: shown.root, change: shown.change.id,
    to: thread.data.comments[-1].id, draft: ''}
  var last = thread.data.comments[-1]
  execute $'new memex://reply/{thread.id}'
  # Open already: keep the draft it saved
  if exists('b:memex_reply')
    return
  endif
  setlocal buftype=acwrite bufhidden=wipe noswapfile filetype=markdown
  b:memex_reply = reply
  &l:statusline = $'memex reply to {last.author.name}: '
    .. split(last.text, "\n")[0]
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
  Run(reply.root, DRAFT, [reply.change, reply.draft], input,
    (status, records) => {
      if status == 0 && !empty(records)
        reply.draft = records[0].data.comments[0].id
        setbufvar(buf, '&modified', false)
        echo $'vim-memex: draft saved on change {reply.change}'
      endif
    })
enddef

export def Drafts()
  if empty(shown)
    Warn('run :MemexThreads first')
    return
  endif
  var root = shown.root
  var change = shown.change
  Run(root, 'memex discussion drafts "$1"', [change.id], '',
    (status, records) => {
      if status != 0
        return
      endif
      var items = records->mapnew((_, t) => Item(root, t,
        change.data.current))
      setqflist([], ' ', {title: $'memex drafts: {change.data.title}',
        items: items})
      echo $'vim-memex: {len(records)} drafts on change {change.id}'
    })
enddef

export def Publish()
  if empty(shown)
    Warn('run :MemexThreads first')
    return
  endif
  var change = shown.change
  var question = $'Publish your drafts on change {change.id}?'
  if confirm(question, "&Yes\n&No", 2) != 1
    return
  endif
  Run(shown.root, 'memex discussion publish "$1"', [change.id], '{}',
    (status, _) => {
      if status == 0
        echo $'vim-memex: published on change {change.id}'
      endif
    })
enddef

# Tracker: issues and their comments

export def Issue(id: string)
  var root: string
  var issue = id
  if empty(id)
    var entry = Entry(['issue'])
    if empty(entry)
      Warn('no issue here; give its id or run :MemexIssues')
      return
    endif
    root = entry.root
    issue = entry.record.id
  else
    root = Root()
    if empty(root)
      return
    endif
  endif
  Run(root, 'memex tracker issue "$1"', [issue], '', (status, records) => {
    if status == 0 && !empty(records)
      Scratch($'memex://issue/{issue}', IssueLines(records[0]))
      setlocal filetype=markdown
    endif
  })
enddef

def IssueLines(issue: dict<any>): list<string>
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
  return lines
enddef

export def Issues(query: string)
  var root = Root()
  if empty(root)
    return
  endif
  Query(root, 'memex tracker search', [], query, 'issues', query,
    (issue) => ({text: $'{issue.id} {issue.data.status}: {issue.data.title}'}))
enddef

export def Comment(id: string)
  var root = Root()
  if empty(root)
    return
  endif
  execute $'new {fnameescape($"memex://comment/{id}")}'
  # Open already: keep the text written so far
  if exists('b:memex_comment')
    return
  endif
  setlocal buftype=acwrite bufhidden=wipe noswapfile filetype=markdown
  b:memex_comment = {root: root, id: id}
  &l:statusline = $'memex comment on {id}'
  autocmd BufWriteCmd <buffer> SaveComment()
enddef

def SaveComment()
  var comment = b:memex_comment
  var text = join(getline(1, '$'), "\n")->trim()
  if empty(text)
    Warn('empty comment, nothing sent')
    return
  endif
  if confirm($'Send the comment to issue {comment.id}?', "&Yes\n&No", 2) != 1
    return
  endif
  var buf = bufnr()
  Run(comment.root, 'memex tracker comment "$1"', [comment.id], text,
    (status, _) => {
      if status == 0
        setbufvar(buf, '&modified', false)
        echo $'vim-memex: comment sent to issue {comment.id}'
      endif
    })
enddef

export def Transition(id: string, ...words: list<string>)
  var root = Root()
  if empty(root)
    return
  endif
  if empty(words)
    Warn('give the status to move the issue to')
    return
  endif
  var status = join(words)
  if confirm($'Move issue {id} to {status}?', "&Yes\n&No", 2) != 1
    return
  endif
  Run(root, 'memex tracker transition "$1" "$2"', [id, status], '',
    (exit, _) => {
      if exit == 0
        echo $'vim-memex: issue {id} moved to {status}'
      endif
    })
enddef

# CI: runs of a commit, their suites, tests and logs

const FAILED = ['fail', 'timeout', 'error']

# Prints the run RECORDs of COMMIT, any name git knows it by
const RUNS = 'c=$(git rev-parse --verify "$1^{commit}") && memex ci runs "$c"'

export def Runs(commit: string)
  var root = Root()
  if empty(root)
    return
  endif
  var rev = empty(commit) ? 'HEAD' : commit
  Query(root, RUNS, [rev], '', 'runs', rev, (run) => {
    var config = run.data.config
    var words = [run.data.result ?? run.data.status,
      keys(config)->sort()->mapnew((_, k) => config[k])->join('/'),
      run.data.started ?? '']
    return {text: words->filter((_, w) => !empty(w))->join(' ')}
  })
enddef

export def Suites()
  var entry = Entry(['run'])
  if empty(entry)
    Warn('no run here; run :MemexRuns')
    return
  endif
  var id = entry.record.id
  Query(entry.root, 'memex ci suites "$1"', [id], '', 'suites', $'run {id}',
    (suite) => {
      var counts = suite.data.counts
      var text = $'{suite.data.result} {suite.data.name}'
      if !empty(counts)
        text ..= ' (' .. keys(counts)->sort()
          ->mapnew((_, r) => $'{counts[r]} {r}')->join(', ') .. ')'
      endif
      return {text: text}
    })
enddef

export def Tests()
  var entry = Entry(['suite'])
  if empty(entry)
    Warn('no suite here; run :MemexSuites')
    return
  endif
  var suite = entry.record
  Run(entry.root, 'memex ci tests "$1"', [suite.id], '', (status, records) => {
    if status != 0
      return
    endif
    # Failures first; sort() keeps the order within each
    var Passed = (t) => index(FAILED, t.data.result) < 0 ? 1 : 0
    records->sort((a, b) => Passed(a) - Passed(b))
    List(entry.root, 'tests', suite.data.name, records, (test) => {
      var text = $'{test.data.result} {test.data.name}'
      if !empty(test.data.error)
        text ..= $': {test.data.error}'
      endif
      return {text: text}
    })
  })
  echo 'vim-memex: reading tests...'
enddef

# The URL is the entry's text, for gx to open
export def Logs()
  var entry = Entry(['run', 'suite', 'test'])
  if empty(entry)
    Warn('no run, suite or test here; run :MemexRuns')
    return
  endif
  var record = entry.record
  Query(entry.root, 'memex ci logs "$1"', [record.id], '', 'logs',
    $'{record.kind} {get(record.data, "name", record.id)}',
    (log) => ({text: $'{log.data.name}: {log.data.url}'}))
enddef

export def Retest()
  var entry = Entry(['run'])
  if empty(entry)
    Warn('no run here; run :MemexRuns')
    return
  endif
  var id = entry.record.id
  var reason = input($'Why retest run {id}? ')
  if empty(reason)
    Warn('no reason given, nothing retested')
    return
  endif
  if confirm($'Retest run {id}: {reason}?', "&Yes\n&No", 2) != 1
    return
  endif
  Run(entry.root, 'memex ci retest "$1"', [id], json_encode({reason: reason}),
    (status, _) => {
      if status == 0
        echo $'vim-memex: retest of run {id} asked for'
      endif
    })
enddef

# Code: versions of a change and workspaces of the repository

# Lists the versions of the change at the cursor: of the commit or the
# review thread there, else of HEAD
export def Versions()
  var entry = Entry(['commit'])
  if !empty(entry)
    if empty(entry.record.data.identity)
      Warn($'commit {entry.record.id} has no change identity')
    else
      ListVersions(entry.root, entry.record.data.identity[1])
    endif
    return
  endif
  if !empty(Here())
    var ids = shown.change.links->copy()->filter((_, l) => l[0] == 'change-id')
    if empty(ids)
      Warn($'change {shown.change.id} has no change-id')
    else
      ListVersions(shown.root, ids[0][1])
    endif
    return
  endif
  var root = Root()
  if empty(root)
    return
  endif
  Run(root, 'memex code commits "$(git rev-parse HEAD)^!"', [], '',
    (status, records) => {
      if status != 0
        return
      endif
      if empty(records) || empty(records[0].data.identity)
        Warn('HEAD has no change identity')
      else
        ListVersions(root, records[0].data.identity[1])
      endif
    })
enddef

def ListVersions(root: string, identity: string)
  Query(root, 'memex code versions "$1"', [identity], '', 'versions',
    identity, (commit) => ({text: $'{commit.data.commit[: 11]} '
      .. $'{commit.data.subject} [{commit.data.where->join(", ")}]'}))
enddef

export def Workspaces()
  var root = Root()
  if empty(root)
    return
  endif
  Query(root, 'memex code workspaces', [], '', 'workspaces', root,
    (workspace) => {
      var data = workspace.data
      var text = $'{data.branch ?? "(detached)"} {data.head[: 11]}'
      if data.changed == true
        text ..= ' [changed]'
      endif
      return {filename: data.path, text: text}
    })
enddef
