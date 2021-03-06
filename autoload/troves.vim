" autoload/troves.vim
" Author:       Lowe Thiderman <lowe.thiderman@gmail.com>
" Github:       https://github.com/thiderman/vim-troves

if exists('g:autoloaded_troves') || &cp
  finish
endif
let g:autoloaded_troves = '0.1'

let s:cpo_save = &cpo
set cpo&vim

" Variables and setup {{{

if !exists('g:troves_url')
  let g:troves_url = 'https://pypi.python.org/pypi?%3Aaction=list_classifiers'
endif

if !exists('g:troves_cache')
  let g:troves_cache = '~/.cache/vim-troves/troves.txt'
endif
let g:troves_cache = expand(g:troves_cache)

" Make sure that the cache directory exists
let s:cachedir = fnamemodify(g:troves_cache, ':h')
if !isdirectory(s:cachedir)
  call mkdir(s:cachedir, 'p')
endif

" }}}
" Intialization and utility functions {{{

function! troves#Init()
  call troves#Download()
  set omnifunc=troves#TroveComplete

  " pythonEscape was chosen since pythonString already allows it in contains=.
  " Re-using it reduces the amount of trickery needed.
  syn match pythonEscape ' :: ' contained

  com! -buffer -bang -nargs=0 Troves call troves#Command(<bang>0)
endfunction

function! troves#Load()
  let troves = {}
  for line in readfile(g:troves_cache)
    let troves = s:parse(troves, split(line, ' :: '))
  endfor
  return troves
endfunction

function! s:parse(struct, body)
  " Recursively parse the :: structure into dictionaries so that we can
  " traverse them a bit easier.
  let struct = a:struct

  let key = a:body[0]
  if !has_key(struct, key)
    let struct[key] = {}
  endif

  if len(a:body) > 1
    call extend(struct[key], s:parse(struct[key], a:body[1:]))
  endif
  return struct
endfunction

function! troves#Download()
  " Downloads the troves in the background using curl
  if !filereadable(g:troves_cache)
    silent exe "!curl --silent -o" g:troves_cache shellescape(g:troves_url, 1) '&'
    echo "Downloading troves in background"
  endif
endfunction

function! troves#Refresh()
  if filereadable(g:troves_cache)
    call delete(g:troves_cache)
  endif
  call troves#Download()
endfunction

function! troves#Command(bang)
  if a:bang
    return troves#Refresh()
  endif

  split `=g:troves_cache`
endfunction

" }}}
" Complete function! {{{

function! troves#TroveComplete(findstart, base)
  if !exists('b:troves')
    let b:troves = troves#Load()
  endif

  " a:findstart is 1, this is the index finder run
  if a:findstart == 1
    let line = getline('.')

    " Colon line; start at the last occurance of " :: "
    let colon = match(line, '.*:: \zs')
    if colon != -1
      return colon
    endif

    " Normal line; match beginning of line or first \w.
    return match(line, '^\W*\zs\w')

  " a:findstart is zero, this is not a drill!
  else
    let ret = []
    let data = b:troves

    " Clear the line from anything before the forst \w
    let line = substitute(getline('.'), '^\W\+', '', '')

    " Figure out which level to work from.
    for cat in split(line, ' :: ')
      if has_key(data, cat)
        let data = data[cat]
      endif
    endfor

    for key in sort(keys(data))
      if len(data[key]) > 0
        " If the key has children, add the double colon.
        let key .= ' :: '
      endif
      let ret = add(ret, key)
    endfor

    " Finally, filter on the input
    return filter(ret, 'v:val =~ "^'.a:base.'"')
  endif
endfunction

" }}}
" autocut {{{

function! troves#AutoCut()
  " Automatically cut of trailing double colons when leaving insert mode.
  " That way, the user can accept troves like 'Programming Language :: Python'
  " which are valid troves by themselves but do have children which will
  " trigger the trailing double colon for the next level of troves.

  call setline('.', substitute(getline('.'), '\zs :: \?\ze\W*$', '', ''))
endfunction

" }}}
" Browser functions {{{

function! troves#BrowserInit()
  call troves#BrowserSyntax()

  " Folding for fun and profit!
  setl foldexpr=troves#BrowserFold\(v:lnum\)
  setl foldtext=troves#BrowserFoldText\(v:foldstart,\ v:foldend\)
  setl foldmethod=expr
  setl textwidth=79

  " Map enter to select the current trove to clipboard and close the window
  nnoremap <silent> <buffer> <cr> :call troves#BrowserSelect()<cr>
endfunction

function! troves#BrowserSyntax()
  syn clear
  syn match troveComment "#.*$"
  syn match troveDoubleColon " :: "

  " vim syntax, you beat me once again...
  syn match troveLevel1 "^\zs[a-zA-Z ]\{-}\ze :: "
  " syn match troveLevel2 "[^:]*$"

  hi link troveComment Comment
  hi link troveDoubleColon Special
  hi link troveLevel1 Preproc
  " hi link troveLevel2 Type
endfunction

function! troves#BrowserFold(lnum)
  let line = getline(a:lnum)
  if line =~ '^#' || line == ''
    return 0
  endif

  let prev = getline(a:lnum - 1)
  if prev == '' || split(line, ' :: ')[0] != split(prev, ' :: ')[0]
    return '>1'
  else
    return 1
  endif
endfunction

function! troves#BrowserFoldText(start, end)
  let word = split(getline(a:start), ' :: ')[0] . ' '
  let end = ' ' .(a:end - a:start). ' troves'
  let fill = repeat('-', &tw - len(word) - len(end))
  return word . fill . end
endfunction

function! troves#BrowserSelect()
  let line = getline('.')
  call setreg('"', line)
  q
  redraw!
  echo "Trove '" . line . "' at top of clipboard"
endfunction

" }}}

let &cpo = s:cpo_save
