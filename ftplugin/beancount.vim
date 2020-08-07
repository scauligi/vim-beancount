if exists('b:did_ftplugin')
    finish
endif

let b:did_ftplugin = 1
let b:undo_ftplugin = 'setlocal foldmethod< foldlevel< foldcolumn< comments< commentstring<'

setl regexpengine=1
setl foldmethod=syntax
setl foldlevel=1
setl foldcolumn=4
setl comments=b:;
setl commentstring=;%s
compiler beancount

" This variable customizes the behavior of the AlignCommodity command.
if !exists('g:beancount_separator_col')
    let g:beancount_separator_col = 50
endif
if !exists('g:beancount_account_completion')
    let g:beancount_account_completion = 'default'
endif
if !exists('g:beancount_detailed_first')
    let g:beancount_detailed_first = 0
endif

command! -buffer -range AlignCommodity
            \ :call beancount#align_commodity(<line1>, <line2>)

command! -buffer GetContext
            \ :call beancount#get_context()

command! -buffer GetLinked
            \ :call beancount#get_linked()

command! -buffer ExplodeFolds
            \ :call beancount#explode_folds()

" Omnifunc for account completion.
setl omnifunc=beancount#complete

let maplocalleader = ","
nnoremap <buffer> <LocalLeader>c :GetContext<CR>
nnoremap <buffer> <LocalLeader>l :GetLinked<CR>
nnoremap <buffer> <LocalLeader>/ :ExplodeFolds<CR>
