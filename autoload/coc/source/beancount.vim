function! coc#source#beancount#init() abort
  return #{
              \ filetypes: ['beancount'],
              \ shortcut: 'bean',
              \ firstMatch: 0,
          \ }
endfunction

function! coc#source#beancount#get_startcol(opt) abort
    let l:col = searchpos('\s', 'bn', a:opt['linenr'])[1]
    if count(map(synstack(a:opt['linenr'], a:opt['colnr']), "synIDattr(v:val, 'name')"), 'beanString', 1)
        let l:col = searchpos('\s"', 'bn', a:opt['linenr'])[1]
    endif
    return l:col
endfunction

function! coc#source#beancount#complete(opt, cb) abort
    let l:partial_line = strpart(a:opt['line'], 0, a:opt['colnr']-1)
    " Match directive types
    if l:partial_line =~# '^\d\d\d\d\(-\|/\)\d\d\1\d\d $'
        call a:cb(beancount#complete_basic(s:directives, a:opt['input'], ''))
    endif

    " If we are using python3, now is a good time to load everything
    call beancount#load_everything()

    " Split out the first character (for cases where we don't want to match the
    " leading character: ", #, etc)
    let l:first = strpart(a:opt['input'], 0, 1)
    let l:rest = strpart(a:opt['input'], 1)

    if l:partial_line =~# '^\d\d\d\d\(-\|/\)\d\d\1\d\d event $' && l:first ==# '"'
        call a:cb(beancount#complete_basic(b:beancount_events, l:rest, '"', '"'))
    endif

    " let l:two_tokens = searchpos('\S\+\s', 'bn', a:opt['linenr'])[1]
    " let l:prev_token = strpart(a:opt['line'], l:two_tokens, a:opt['colnr'] - l:two_tokens)
    let l:prev_token = matchstr(l:partial_line, '\S\+\s$')
    " Match curriences if previous token is number
    if l:prev_token =~# '^\d\+\([\.,]\d\+\)*'
        call a:cb(beancount#complete_basic(b:beancount_currencies, a:opt['input'], ''))
    endif

    if l:first ==# '#'
        call a:cb(beancount#complete_basic(b:beancount_tags, l:rest, '#'))
    elseif l:first ==# '^'
        call a:cb(beancount#complete_basic(b:beancount_links, l:rest, '^'))
    elseif l:first ==# '"'
        call a:cb(beancount#complete_basic(b:beancount_payees, l:rest, '"', '"'))
    else
        call a:cb(beancount#complete_basic(b:beancount_accounts, a:opt['input'], ''))
    endif
endfunction
