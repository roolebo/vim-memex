vim9script
# Review threads of a change, from `memex discussion`, in the quickfix
# list and after the lines they are about; replies to them as drafts.

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

def Root(): string
  var dir = expand('%:p:h')
  if !isdirectory(dir)
    dir = getcwd()
  endif
  var git = $'git -C {shellescape(dir)}'
  var root = trim(system($'{git} rev-parse --show-toplevel'))
  return v:shell_error == 0 ? root : ''
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
    if job.status != 0
      var err = trim(job.err)
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

# Prints the change RECORD of CHANGE, or of HEAD without it, then its
# thread RECORDs
const THREADS = 'if [ -n "$1" ]; then c=$(memex discussion change "$1");'
  .. ' else c=$(memex discussion locate "$(git rev-parse HEAD)"); fi'
  .. ' || exit 1; printf "%s\n" "$c";'
  .. ' memex discussion threads "$(printf "%s" "$c" | jq -r .id)"'

export def Threads(all: bool, change: string)
  var root = Root()
  if empty(root)
    Warn('not in a git working copy')
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
    var list = getqflist({idx: 0, items: 0})
    id = get(list.items[list.idx - 1], 'user_data', '')
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
