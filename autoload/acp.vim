"=============================================================================
" Copyright (c) 2007-2009 Takeshi NISHIDA
"
"=============================================================================
" LOAD GUARD {{{1

if !l9#guardScriptLoading(expand('<sfile>:p'), 0, 0, [])
  finish
endif

" }}}1
"=============================================================================
" GLOBAL FUNCTIONS: {{{1

"
function acp#enable()
  call acp#disable()

  augroup AcpGlobalAutoCommand
    autocmd!
    autocmd InsertEnter * unlet! s:posLast s:lastUncompletable
    autocmd InsertLeave * call s:finishPopup(1)
  augroup END

  autocmd AcpGlobalAutoCommand CursorMovedI * call s:feedPopup()
  autocmd AcpGlobalAutoCommand InsertCharPre * call s:reFeedCond()

  nnoremap <silent> i i<C-r>=<SID>feedPopup()<CR>
  nnoremap <silent> a a<C-r>=<SID>feedPopup()<CR>
  nnoremap <silent> R R<C-r>=<SID>feedPopup()<CR>
endfunction

"
function acp#disable()
  augroup AcpGlobalAutoCommand
    autocmd!
  augroup END
  nnoremap i <Nop> | nunmap i
  nnoremap a <Nop> | nunmap a
  nnoremap R <Nop> | nunmap R
endfunction

"
function acp#lock()
  let s:lockCount += 1
endfunction

"
function acp#unlock()
  let s:lockCount -= 1
  if s:lockCount < 0
    let s:lockCount = 0
    throw "AutoComplPop: not locked"
  endif
endfunction

"
function acp#meetsForSnipmate(context)
  if g:acp_behaviorSnipmateLength < 0
    return 0
  endif
  let matches = matchlist(a:context, '\(^\|\s\|\<\)\(\u\{' .
        \                            g:acp_behaviorSnipmateLength . ',}\)$')
  return !empty(matches) && !empty(s:getMatchingSnipItems(matches[2]))
endfunction

"
function acp#meetsForKeyword(context)
  if g:acp_behaviorKeywordLength < 0
    return 0
  endif
  let matches = matchlist(a:context, '\(\k\{' . g:acp_behaviorKeywordLength . ',}\)$')
  if empty(matches)
    return 0
  endif
  for ignore in g:acp_behaviorKeywordIgnores
    if stridx(ignore, matches[1]) == 0
      return 0
    endif
  endfor
  return 1
endfunction

"
function acp#meetsForFile(context)
  if g:acp_behaviorFileLength < 0
    return 0
  endif
  if has('win32') || has('win64')
    let separator = '[/\\]'
  else
    let separator = '\/'
  endif
  if a:context !~ '\f' . separator . '\f\{' . g:acp_behaviorFileLength . ',}$'
    return 0
  endif
  return a:context !~ '[*/\\][/\\]\f*$\|[^[:print:]]\f*$'
endfunction

"
function acp#meetsForRubyOmni(context)
  if !has('ruby')
    return 0
  endif
  if g:acp_behaviorRubyOmniMethodLength >= 0 &&
        \ a:context =~ '[^. \t]\(\.\|::\)\k\{' .
        \              g:acp_behaviorRubyOmniMethodLength . ',}$'
    return 1
  endif
  if g:acp_behaviorRubyOmniSymbolLength >= 0 &&
        \ a:context =~ '\(^\|[^:]\):\k\{' .
        \              g:acp_behaviorRubyOmniSymbolLength . ',}$'
    return 1
  endif
  return 0
endfunction

"
function acp#meetsForPythonOmni(context)
  if !has('python') || g:acp_behaviorPythonOmniLength < 0
    return 0
  endif
  if g:acp_behaviorPythonOmniLength == 0
    return 1
  endif
  let matches = matchlist(a:context, '\(\(\k\|\.\|(\)\{' . g:acp_behaviorPythonOmniLength . ',}\)$')
  if empty(matches)
    return 0
  endif
  return 1
endfunction

"
function acp#meetsForPerlOmni(context)
  return g:acp_behaviorPerlOmniLength >= 0 &&
        \ a:context =~ '\w->\k\{' . g:acp_behaviorPerlOmniLength . ',}$'
endfunction

"
function acp#meetsForXmlOmni(context)
  return g:acp_behaviorXmlOmniLength >= 0 &&
        \ a:context =~ '\(<\|<\/\|<[^>]\+ \|<[^>]\+=\"\)\k\{' .
        \              g:acp_behaviorXmlOmniLength . ',}$'
endfunction

"
function acp#meetsForHtmlOmni(context)
    if g:acp_behaviorHtmlOmniLength >= 0
        if a:context =~ '\(<\|<\/\|<[^>]\+ \|<[^>]\+=\"\)\k\{' .g:acp_behaviorHtmlOmniLength . ',}$'
            return 1
        elseif a:context =~ '\(\<\k\{1,}\(=\"\)\{0,1}\|\" \)$'
            let cur = line('.')-1
            while cur > 0
                let lstr = getline(cur)
                if lstr =~ '>[^>]*$'
                    return 0
                elseif lstr =~ '<[^<]*$'
                    return 1
                endif
                let cur = cur-1
            endwhile
            return 0
        endif
    else
        return 0
    endif
endfunction

"
function acp#meetsForCssOmni(context)
  if g:acp_behaviorCssOmniPropertyLength >= 0 &&
        \ a:context =~ '\(^\s\|[;{]\)\s*\k\{' .
        \              g:acp_behaviorCssOmniPropertyLength . ',}$'
    return 1
  endif
  if g:acp_behaviorCssOmniValueLength >= 0 &&
        \ a:context =~ '[:@!]\s*\k\{' .
        \              g:acp_behaviorCssOmniValueLength . ',}$'
    return 1
  endif
  return 0
endfunction

"
function acp#meetsForJavaScriptOmni(context)
    let matches = matchlist(a:context, '\(\k\{1}\)$')
    if empty(matches)
        return 0
    endif
    return 1
endfunction

"
function acp#completeSnipmate(findstart, base)
  if a:findstart
    let s:posSnipmateCompletion = len(matchstr(s:getCurrentText(), '.*\U'))
    return s:posSnipmateCompletion
  endif
  let lenBase = len(a:base)
  let items = filter(GetSnipsInCurrentScope(),
        \            'strpart(v:key, 0, lenBase) ==? a:base')
  return map(sort(items(items)), 's:makeSnipmateItem(v:val[0], v:val[1])')
endfunction

"
function acp#onPopupCloseSnipmate()
  let word = s:getCurrentText()[s:posSnipmateCompletion :]
  for trigger in keys(GetSnipsInCurrentScope())
    if word ==# trigger
      call feedkeys("\<C-r>=TriggerSnippet()\<CR>", "n")
      return 0
    endif
  endfor
  return 1
endfunction

"
function acp#onPopupPost()
  " to clear <C-r>= expression on command-line
  echo ''
  if pumvisible() && exists('s:behavsCurrent[s:iBehavs]')
    inoremap <silent> <expr> <C-h> acp#onBs()
    inoremap <silent> <expr> <BS>  acp#onBs()
    let l:autoselect_up = ""
    let l:autoselect_down = ""
    if g:acp_autoselectFirstCompletion
        let l:autoselect_up = "\<Up>"
        let l:autoselect_down = "\<Down>"
    endif
    " a command to restore to original text and select the first match
    return (s:behavsCurrent[s:iBehavs].command =~# "\<C-p>"
          \             ? "\<C-n>" . l:autoselect_up
          \             : "\<C-p>" . l:autoselect_down)
  endif
  let s:iBehavs += 1
  if len(s:behavsCurrent) > s:iBehavs 
    call s:setCompletefunc()
    call acp#pum_color_and_map_adaptions(0)
    return printf("\<C-e>%s\<C-r>=acp#onPopupPost()\<CR>",
          \       s:behavsCurrent[s:iBehavs].command)
  else
    let s:lastUncompletable = {
          \   'word': s:getCurrentWord(),
          \   'commands': map(copy(s:behavsCurrent), 'v:val.command')[1:],
          \ }
    call s:finishPopup(0)
    return "\<C-e>"
  endif
endfunction

function acp#pum_color_and_map_adaptions(force_direction)
    " force_direction
    " 0 : no forcing, command conditional acp selection
    " 1 : force forward
    " 2 : force reverse

    " Calculate the direction
    let l:direction = a:force_direction
    if a:force_direction == 0
        if s:behavsCurrent[s:iBehavs].command =~? "\<C-p>"
            let l:direction = 2
        else
            let l:direction = 1
        endif
    endif

    " Switch the mappings if requested
    if l:direction == 2 && g:acp_reverseMappingInReverseMenu
        let l:nextMap = g:acp_previousItemMapping
        let l:prevMap = g:acp_nextItemMapping
    else
        let l:nextMap = g:acp_nextItemMapping
        let l:prevMap = g:acp_previousItemMapping
    endif
    execute 'inoremap ' . l:nextMap[0]
                \ . ' <C-R>=pumvisible() ? "\<lt>C-N>" : "'
                \ . l:nextMap[1] . '"<CR>'
    execute 'inoremap ' . l:prevMap[0]
                \ . ' <C-R>=pumvisible() ? "\<lt>C-P>" : "'
                \ . l:prevMap[1] . '"<CR>'

    " Switch colors
    if l:direction == 1
        execute "hi! link Pmenu " . g:acp_colorForward
    elseif l:direction == 2
        execute "hi! link Pmenu " . g:acp_colorReverse
    else
        throw "acp: color/map adaption: Invalid direction argument"
    endif

    return ''
endfunction

"
function acp#onBs()
  " using "matchstr" and not "strpart" in order to handle multi-byte
  " characters
  if call(s:behavsCurrent[s:iBehavs].meets,
        \ [matchstr(s:getCurrentText(), '.*\ze.')])
    return "\<BS>"
  endif
  return "\<C-e>\<BS>"
endfunction

" }}}1
"=============================================================================
" LOCAL FUNCTIONS: {{{1

function s:getKeywordCharConfig()
    if exists("b:acp_keyword_chars_for_checkpoint")
        return b:acp_keyword_chars_for_checkpoint
    elseif exists("g:acp_keyword_chars_for_checkpoint")
        return g:acp_keyword_chars_for_checkpoint
    endif
    return ''
endfun

function s:getCheckpointMatchPattern()
    let l:additional_chars = s:getKeywordCharConfig()
    if len(l:additional_chars) == 0
        return '\w*$'
    elseif l:additional_chars == '&iskeyword'
        return '\k*$'
    else
        return '\(\w\|['. l:additional_chars . ']\)*$'
        "return '[[:alnum:]_'. l:additional_chars . ']*$'
endfun

"
function s:wantAlwaysReFeed()
    " user has requested to always refeed after every char
    if exists("b:acp_refeed_after_every_char")
        if b:acp_refeed_after_every_char
            return 1
        endif
    elseif exists("g:acp_refeed_after_every_char")
        if g:acp_refeed_after_every_char
            return 1
        endif
    endif
    return 0
endfun

function s:getReFeedCheckpoints()
    if exists("b:acp_refeed_checkpoints")
        return b:acp_refeed_checkpoints
    elseif exists("g:acp_refeed_checkpoints")
        return g:acp_refeed_checkpoints
    endif
    return []
endfun

function s:isReFeedCheckpoint()
    let l:all_checkpoints = s:getReFeedCheckpoints()
    if empty(l:all_checkpoints)
        return 0
    endif
    let l:pattern = s:getCheckpointMatchPattern()
    let l:current_alnum_word = matchstr(s:getCurrentText(), l:pattern)
    let l:curren_alnum_length = strwidth(l:current_alnum_word)
    for l:checkpoint in l:all_checkpoints
        " There is a char about to be inserter (InsertCharPre)
        if l:checkpoint == (l:curren_alnum_length + 1)
            return 1
        endif
    endfor
    return 0
endfunction

"
function s:reFeedCond()
    if s:wantAlwaysReFeed() || s:isReFeedCheckpoint()
        if v:char != ' '
            unlet! s:posLast s:lastUncompletable
            call s:feedPopup()
        endif
    endif
endfun

"
function s:getCurrentWord()
  return matchstr(s:getCurrentText(), '\k*$')
endfunction

"
function s:getCurrentText()
  return strpart(getline('.'), 0, col('.') - 1)
endfunction

"
function s:getPostText()
  return strpart(getline('.'), col('.') - 1)
endfunction

"
function s:isModifiedSinceLastCall()
  if exists('s:posLast')
    let posPrev = s:posLast
    let nLinesPrev = s:nLinesLast
    let textPrev = s:textLast
  endif
  let s:posLast = getpos('.')
  let s:nLinesLast = line('$')
  let s:textLast = getline('.')
  if !exists('posPrev')
    return 1
  elseif posPrev[1] != s:posLast[1] || nLinesPrev != s:nLinesLast
    return (posPrev[1] - s:posLast[1] == nLinesPrev - s:nLinesLast)
  elseif textPrev ==# s:textLast
    return 0
  elseif posPrev[2] > s:posLast[2]
    return 1
  elseif has('gui_running') && has('multi_byte')
    " NOTE: auto-popup causes a strange behavior when IME/XIM is working
    return posPrev[2] + 1 == s:posLast[2]
  endif
  return posPrev[2] != s:posLast[2]
endfunction

"
function s:makeCurrentBehaviorSet()
  let modified = s:isModifiedSinceLastCall()
  if exists('s:behavsCurrent[s:iBehavs].repeat') && s:behavsCurrent[s:iBehavs].repeat
    let behavs = [ s:behavsCurrent[s:iBehavs] ]
  " This alledgedly fixed a bug, but with it, autocomplete does not trigger
  " immediately after a previous completion finishes. For example:
  " foo<complete>.<popup>, the popup does not popup right away.
  " elseif exists('s:behavsCurrent[s:iBehavs]')
  "   return []
  elseif modified
    let behavs = copy(exists('g:acp_behavior[&filetype]')
          \           ? g:acp_behavior[&filetype]
          \           : g:acp_behavior['*'])
  else
    return []
  endif
  let text = s:getCurrentText()
  call filter(behavs, 'call(v:val.meets, [text])')
  let s:iBehavs = 0
  if exists('s:lastUncompletable') &&
        \ stridx(s:getCurrentWord(), s:lastUncompletable.word) == 0 &&
        \ map(copy(behavs), 'v:val.command') ==# s:lastUncompletable.commands
    let behavs = []
  else
    unlet! s:lastUncompletable
  endif
  return behavs
endfunction

"
function s:feedPopup()
  " NOTE: CursorMovedI is not triggered while the popup menu is visible. And
  "       it will be triggered when popup menu is disappeared.
  if s:lockCount > 0 || &paste
    return ''
  endif
  if exists('s:behavsCurrent[s:iBehavs].onPopupClose')
    if !call(s:behavsCurrent[s:iBehavs].onPopupClose, [])
      call s:finishPopup(1)
      return ''
    endif
  endif
  let s:behavsCurrent = s:makeCurrentBehaviorSet()
  if empty(s:behavsCurrent)
    call s:finishPopup(1)
    return ''
  endif
  " In case of dividing words by symbols (e.g. "for(int", "ab==cd") while a
  " popup menu is visible, another popup is not available unless input <C-e>
  " or try popup once. So first completion is duplicated.
  call insert(s:behavsCurrent, s:behavsCurrent[s:iBehavs])
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&spell', 0)
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&completeopt', 'menuone' . (g:acp_completeoptPreview ? ',preview' : ''))
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&complete', g:acp_completeOption)
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&ignorecase', g:acp_ignorecaseOption)
  " NOTE: With CursorMovedI driven, Set 'lazyredraw' to avoid flickering.
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
        \ '&lazyredraw', 1)
  " NOTE: 'textwidth' must be restored after <C-e>.
  call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP1,
        \ '&textwidth', 0)

  call acp#pum_color_and_map_adaptions(0)

  call s:setCompletefunc()
  call feedkeys(s:behavsCurrent[s:iBehavs].command . "\<C-r>=acp#onPopupPost()\<CR>", 'n')
  return '' " this function is called by <C-r>=
endfunction

"
function s:finishPopup(fGroup1)
  inoremap <C-h> <Nop> | iunmap <C-h>
  inoremap <BS>  <Nop> | iunmap <BS>
  let s:behavsCurrent = []
  call l9#tempvariables#end(s:TEMP_VARIABLES_GROUP0)
  if a:fGroup1
    call l9#tempvariables#end(s:TEMP_VARIABLES_GROUP1)
  endif
endfunction

"
function s:setCompletefunc()
  if exists('s:behavsCurrent[s:iBehavs].completefunc')
    call l9#tempvariables#set(s:TEMP_VARIABLES_GROUP0,
          \ '&completefunc', s:behavsCurrent[s:iBehavs].completefunc)
  endif
endfunction

"
function s:makeSnipmateItem(key, snip)
  if type(a:snip) == type([])
    let descriptions = map(copy(a:snip), 'v:val[0]')
    let snipFormatted = '[MULTI] ' . join(descriptions, ', ')
  else
    let snipFormatted = substitute(a:snip, '\(\n\|\s\)\+', ' ', 'g')
  endif
  return  {
        \   'word': a:key,
        \   'menu': strpart(snipFormatted, 0, 80),
        \ }
endfunction

"
function s:getMatchingSnipItems(base)
  let key = a:base . "\n"
  if !exists('s:snipItems[key]')
    let s:snipItems[key] = items(GetSnipsInCurrentScope())
    call filter(s:snipItems[key], 'strpart(v:val[0], 0, len(a:base)) ==? a:base')
    call map(s:snipItems[key], 's:makeSnipmateItem(v:val[0], v:val[1])')
  endif
  return s:snipItems[key]
endfunction

" }}}1
"=============================================================================
" INITIALIZATION {{{1

let s:TEMP_VARIABLES_GROUP0 = "AutoComplPop0"
let s:TEMP_VARIABLES_GROUP1 = "AutoComplPop1"
let s:lockCount = 0
let s:behavsCurrent = []
let s:iBehavs = 0
let s:snipItems = {}

" }}}1
"=============================================================================
" vim: set fdm=marker:
