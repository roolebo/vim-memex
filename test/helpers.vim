vim9script
# Functions the tests call through --remote-expr

# The quickfix list, an entry a line: FILE:LNUM:TEXT, FILE relative to
# the current directory
def g:Qf(): string
  return getqflist()->mapnew((_, i) =>
    $'{i.bufnr > 0 ? bufname(i.bufnr)->fnamemodify(":.") : ""}:'
    .. $'{i.lnum}:{i.text}')->join("\n")
enddef

# The texts shown after line LNUM of FILE, joined with |
def g:After(file: string, lnum: number): string
  return prop_list(lnum, {bufnr: bufnr(file)})
    ->mapnew((_, p) => get(p, 'text', ''))->join('|')
enddef
