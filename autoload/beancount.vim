let s:path = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let s:using_python3 = has('job')

" Equivalent to python's startswith
" Matches ignoring case
function! s:startswith(string, prefix) abort
    return strpart(a:string, 0, strlen(a:prefix)) ==? a:prefix
endfunction

" Align currency on decimal point.
function! beancount#align_commodity(line1, line2) abort
    " Save cursor position to adjust it if necessary.
    let l:cursor_col = col('.')
    let l:cursor_line = line('.')

    " Increment at start of loop, because of continue statements.
    let l:current_line = a:line1 - 1
    while l:current_line < a:line2
        let l:current_line += 1
        let l:line = getline(l:current_line)
        " This matches an account name followed by a space in one of the two
        " following cases:
        "  - A posting line, i.e., the line starts with indentation followed
        "    by an optional flag and the account.
        "  - A balance directive, i.e., the line starts with a date followed
        "    by the 'balance' keyword and the account.
        "  - A price directive, i.e., the line starts with a date followed by
        "    the 'price' keyword and a currency.
        let l:end_account = matchend(l:line, '\v' .
            \ '^[\-/[:digit:]]+\s+balance\s+([A-Z][A-Za-z0-9\-]+)(:[A-Z0-9][A-Za-z0-9\-]*)+ ' .
            \ '|^[\-/[:digit:]]+\s+price\s+\S+ ' .
            \ '|^\s+([!&#?%PSTCURM]\s+)?([A-Z][A-Za-z0-9\-]+)(:[A-Z0-9][A-Za-z0-9\-]*)+ '
            \ )
        if l:end_account < 0
            continue
        endif

        " Where does the number begin?
        let l:begin_number = matchend(l:line, '^ *', l:end_account)

        " Look for a minus sign and a number (possibly containing commas) and
        " align on the next column.
        let l:separator = matchend(l:line, '^\v([-+])?[,[:digit:]]+', l:begin_number) + 1
        if l:separator < 0 | continue | endif
        let l:has_spaces = l:begin_number - l:end_account
        let l:need_spaces = g:beancount_separator_col - l:separator + l:has_spaces
        if l:need_spaces < 0 | continue | endif
        call setline(l:current_line, l:line[0 : l:end_account - 1] . repeat(' ', l:need_spaces) . l:line[ l:begin_number : -1])
        if l:current_line == l:cursor_line && l:cursor_col >= l:end_account
            " Adjust cursor position for continuity.
            call cursor(0, l:cursor_col + l:need_spaces - l:has_spaces)
        endif
    endwhile
endfunction

function! s:count_expression(text, expression) abort
    return len(split(a:text, a:expression, 1)) - 1
endfunction

function! s:sort_accounts_by_depth(name1, name2) abort
    let l:depth1 = s:count_expression(a:name1, ':')
    let l:depth2 = s:count_expression(a:name2, ':')
    return l:depth1 == l:depth2 ? 0 : l:depth1 > l:depth2 ? 1 : -1
endfunction

let s:directives = ['open', 'close', 'commodity', 'txn', 'balance', 'pad', 'note', 'document', 'price', 'event', 'query', 'custom']

" ------------------------------
" Completion functions
" ------------------------------
function! beancount#complete(findstart, base) abort
    if a:findstart
        let l:col = searchpos('\s', 'bn', line('.'))[1]
        if count(map(synstack(line("."), col(".")), "synIDattr(v:val, 'name')"), 'beanString', 1)
          let l:col = searchpos('\s"', 'bn', line('.'))[1]
        endif
        if l:col == 0
            return -1
        else
            return l:col
        endif
    endif

    let l:partial_line = strpart(getline('.'), 0, getpos('.')[2]-1)
    " Match directive types
    if l:partial_line =~# '^\d\d\d\d\(-\|/\)\d\d\1\d\d $'
        return beancount#complete_basic(s:directives, a:base, '')
    endif

    " If we are using python3, now is a good time to load everything
    call beancount#load_everything()

    " Split out the first character (for cases where we don't want to match the
    " leading character: ", #, etc)
    let l:first = strpart(a:base, 0, 1)
    let l:rest = strpart(a:base, 1)

    if l:partial_line =~# '^\d\d\d\d\(-\|/\)\d\d\1\d\d event $' && l:first ==# '"'
        return beancount#complete_basic(b:beancount_events, l:rest, '"', '"')
    endif

    let l:two_tokens = searchpos('\S\+\s', 'bn', line('.'))[1]
    let l:prev_token = strpart(getline('.'), l:two_tokens, getpos('.')[2] - l:two_tokens)
    " Match curriences if previous token is number
    if l:prev_token =~# '^\d\+\([\.,]\d\+\)*'
        call beancount#load_currencies()
        return beancount#complete_basic(b:beancount_currencies, a:base, '')
    endif

    if l:first ==# '#'
        call beancount#load_tags()
        return beancount#complete_basic(b:beancount_tags, l:rest, '#')
    elseif l:first ==# '^'
        call beancount#load_links()
        return beancount#complete_basic(b:beancount_links, l:rest, '^')
    elseif l:first ==# '"'
        call beancount#load_payees()
        return beancount#complete_basic(b:beancount_payees, l:rest, '"', '"')
    else
        call beancount#load_accounts()
        " return beancount#complete_account(a:base)
        return beancount#complete_basic(b:beancount_accounts, a:base, '')
    endif
endfunction

function! beancount#get_root() abort
    if exists('b:beancount_root')
        return b:beancount_root
    endif
    let l:rootname = matchstr(getline(2), 'root:\s*\zs.*')
    if l:rootname != ""
      let b:beancount_root = expand('%:p:h') . '/' . l:rootname
      return b:beancount_root
    endif
    return expand('%')
endfunction

function! beancount#dump(ch, msg) abort
  echom a:msg
endfunction

function! beancount#load_everything() abort
    if !exists('b:beancount_loaded')
        let l:root = beancount#get_root()
        let l:script = s:path .. '/' .. 'beancount_load_everything.py'
        let s:job = job_start(["python3", l:script, l:root], #{mode: "json"})
    endif
endfunction

function! beancount#load_accounts() abort
    if !s:using_python3 && !exists('b:beancount_accounts')
        let l:root = beancount#get_root()
        let b:beancount_accounts = beancount#query_single(l:root, 'select distinct account;')
    endif
endfunction

function! beancount#load_tags() abort
    if !s:using_python3 && !exists('b:beancount_tags')
        let l:root = beancount#get_root()
        let b:beancount_tags = beancount#query_single(l:root, 'select distinct tags;')
    endif
endfunction

function! beancount#load_links() abort
    if !s:using_python3 && !exists('b:beancount_links')
        let l:root = beancount#get_root()
        let b:beancount_links = beancount#query_single(l:root, 'select distinct links;')
    endif
endfunction

function! beancount#load_currencies() abort
    if !s:using_python3 && !exists('b:beancount_currencies')
        let l:root = beancount#get_root()
        let b:beancount_currencies = beancount#query_single(l:root, 'select distinct currency;')
    endif
endfunction

function! beancount#load_payees() abort
    if !s:using_python3 && !exists('b:beancount_payees')
        let l:root = beancount#get_root()
        let b:beancount_payees = beancount#query_single(l:root, 'select distinct payee;')
    endif
endfunction

" General completion function
function! beancount#complete_basic(input, base, prefix, suffix = "") abort
    " let l:matches = filter(copy(a:input), 's:startswith(v:val, a:base)')
    let l:matches = matchfuzzy(a:input, a:base)

    return map(l:matches, 'a:prefix . v:val . a:suffix')
endfunction

" Complete account name, ignoring case.
function! beancount#complete_account(base) abort
    if g:beancount_account_completion ==? 'chunks'
        let l:pattern = '\c^\V' . substitute(a:base, ':', '\\[^:]\\*:', 'g') . '\[^:]\*'
    else
        let l:pattern = '\c^\V\.\*' . substitute(a:base, ':', '\\.\\*:\\.\\*', 'g') . '\.\*'
    endif

    let l:matches = []
    let l:index = -1
    while 1
        let l:index = match(b:beancount_accounts, l:pattern, l:index + 1)
        if l:index == -1 | break | endif
        call add(l:matches, matchstr(b:beancount_accounts[l:index], l:pattern))
    endwhile

    if g:beancount_detailed_first
        let l:matches = reverse(sort(l:matches, 's:sort_accounts_by_depth'))
    endif

    return l:matches
endfunction

function! beancount#query_single(root_file, query) abort
python << EOF
import vim
import subprocess
import os

# We intentionally want to ignore stderr so it doesn't mess up our query processing
output = subprocess.check_output(['bean-query', vim.eval('a:root_file'), vim.eval('a:query')], stderr=open(os.devnull, 'w')).split('\n')
output = output[2:]

result_list = [y for y in (x.strip() for x in output) if y]

vim.command('return [{}]'.format(','.join(repr(x) for x in sorted(result_list))))
EOF
endfunction

" Create a preview window for bean-doctor output
function! beancount#create_preview(text) abort
    let l:text = substitute(a:text, ' \+\n', '\n', "g")
    let l:bufnr = bufadd("__bean-doctor__")
    call bufload(l:bufnr)
    call setbufvar(l:bufnr, "&buftype", "nofile")
    call setbufvar(l:bufnr, "&bufhidden", "hide")
    call setbufvar(l:bufnr, "&swapfile", v:false)
    call setbufvar(l:bufnr, "&buflisted", v:false)
    call setbufvar(l:bufnr, "&filetype", "beancount")
    call setbufvar(l:bufnr, "&foldenable", v:false)
    call setbufvar(l:bufnr, "&wrap", v:false)
    call setbufvar(l:bufnr, "&foldcolumn", 0)
    call setbufvar(l:bufnr, "&signcolumn", "no")
    call setbufvar(l:bufnr, "signifycolumn", 1)
    call setbufvar(l:bufnr, "is_beancount_buffer", v:true)
    call deletebufline(l:bufnr, 1, "$")
    call setbufline(l:bufnr, 1, split(l:text, '\n'))
    pclose
    pedit __bean-doctor__
    wincmd P
    20 wincmd _
endfunction


" Call bean-doctor on the current line and dump output into a scratch buffer
function! beancount#get_context() abort
    let l:root = beancount#get_root()
    let l:context = system('bean-doctor context ' . l:root . ' ' . expand('%') . ':' . line('.'))

    let l:context = substitute(l:context, '\n\*', '\n ', "g")

    call beancount#create_preview(l:context)

    call search('^ \* Transaction -\+')
    normal! 2jzt
    wincmd p

    " if exists("t:beancount_buffer")
    "   let l:winnr = bufwinnr(t:beancount_buffer)
    "   if l:winnr == -1
    "     noswapfile keepalt botright 20 new __bean-doctor__
    "     setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
    "   else
    "     execute "keepalt" l:winnr "wincmd w"
    "   endif
    "   normal! gg"_dG
    " else
      " noswapfile keepalt botright 20 new _bean-doctor
      " let b:is_beancount_buffer = v:true
      " let t:beancount_buffer = bufnr()
      " setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
      " setfiletype beancount
      " setlocal nofoldenable nowrap foldcolumn=0 signcolumn=no
    " endif

    " call append(0, split(l:context, '\v\n'))
    " silent %substitute/^\*/ /e
    " call search('^ \* Transaction -\+')
    " normal! 2jzt
    " wincmd p
endfunction

" Call bean-doctor on the current line and dump output into a scratch buffer
function! beancount#get_linked() abort
    let l:root = beancount#get_root()
    let l:context = system('bean-doctor linked ' . l:root . ' ' . expand('%') . ':' . line('.'))
    let l:context = substitute(l:context, "\n   ", "\n", "g")
    call beancount#create_preview(l:context)
    " botright new
    " setlocal buftype=nofile bufhidden=hide noswapfile filetype=beancount nofoldenable nolist
    " call append(0, split(l:context, '\v\n'))
    " %substitute/^   //e
    normal! G
    wincmd p
endfunction

" Expand all folds with prompted pattern
function! beancount#explode_folds() abort
    let l:cur = getcurpos()
    call inputsave()
    let l:pattern = input('/')
    call inputrestore()
    if l:pattern == ""
        return
    endif
    if l:pattern[-1:] != "/"
        let @/ = l:pattern
        let l:pattern .= "/"
    else
        let @/ = l:pattern[:-2]
    endif
    let l:pattern = '/' . l:pattern
    execute  "silent folddoclosed " . l:pattern . " foldopen"
    call setpos('.', l:cur)
    let &hlsearch=1
endfunction

function! beancount#foldtext() abort
  let foldtext = foldtext()
  let nextline = getline(v:foldstart + 1)
  let date = matchstr(nextline, '^\s\+date:\s*\zs\d\{4\}-\d\{2\}-\d\{2\}\ze\s*$')
  if date != ""
    let origdate = matchstr(foldtext, '\d\{4\}-\d\{2\}-\d\{2\}')
    if origdate < date
      let marker = " <"
    elseif origdate > date
      let marker = " >"
    else
      let marker = " *"
    endif
    let foldtext = substitute(foldtext, '\d\{4\}-\d\{2\}-\d\{2\} \*\=', date .. marker, "") .. "  (" .. origdate .. ")"
  endif
  return foldtext
endfunction
