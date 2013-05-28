"=============================================================================
" FILE: complete.vim
" AUTHOR: Shougo Matsushita <Shougo.Matsu@gmail.com>
" Last Modified: 28 May 2013.
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
"=============================================================================

let s:save_cpo = &cpo
set cpo&vim

function! neocomplete#complete#manual_complete(findstart, base) "{{{
  let neocomplete = neocomplete#get_current_neocomplete()

  if a:findstart
    let cur_text = neocomplete#get_cur_text()
    if !neocomplete#is_enabled()
          \ || neocomplete#helper#is_omni_complete(cur_text)
      call neocomplete#helper#clear_result()
      let &l:completefunc = 'neocomplete#complete#manual_complete'

      return (neocomplete#is_prefetch()
            \ || g:neocomplete_enable_insert_char_pre
            \ ) ?
            \ -1 : -3
    endif

    " Get complete_pos.
    if neocomplete#is_prefetch() &&
          \ !empty(neocomplete.complete_sources)
      " Use prefetch results.
    else
      let neocomplete.complete_sources =
            \ neocomplete#complete#_get_results(cur_text)
    endif
    let complete_pos =
          \ neocomplete#complete#_get_complete_pos(
          \ neocomplete.complete_sources)

    if complete_pos < 0
      call neocomplete#helper#clear_result()

      let neocomplete = neocomplete#get_current_neocomplete()
      let complete_pos = (neocomplete#is_prefetch() ||
            \ g:neocomplete_enable_insert_char_pre ||
            \ neocomplete#get_current_neocomplete().skipped) ?  -1 : -3
      let neocomplete.skipped = 0
    endif

    return complete_pos
  else
    " Restore completeselect.
    if has_key(neocomplete, 'completeselect')
          \ && &completeselect != neocomplete.completeselect
      let &completeselect = neocomplete.completeselect
    endif

    let complete_pos = neocomplete#complete#_get_complete_pos(
          \ neocomplete.complete_sources)
    let neocomplete.candidates = neocomplete#complete#_get_words(
          \ neocomplete.complete_sources, complete_pos, a:base)
    let neocomplete.complete_str = a:base

    let dict = { 'words' : neocomplete.candidates }

    if len(a:base) < g:neocomplete_auto_completion_start_length
          \   || !empty(filter(copy(neocomplete.candidates),
          \          "get(v:val, 'neocomplete__refresh', 0)"))
          \   || len(neocomplete.candidates) >= g:neocomplete_max_list
      " Note: If Vim is less than 7.3.561, it have broken register "." problem.
      let dict.refresh = 'always'
    endif

    return dict
  endif
endfunction"}}}

function! neocomplete#complete#sources_manual_complete(findstart, base) "{{{
  let neocomplete = neocomplete#get_current_neocomplete()

  if a:findstart
    if !neocomplete#is_enabled()
      call neocomplete#helper#clear_result()
      return -2
    endif

    " Get complete_pos.
    let complete_sources = neocomplete#complete#_get_results(
          \ neocomplete#get_cur_text(1), neocomplete.manual_sources)
    let neocomplete.complete_pos =
          \ neocomplete#complete#_get_complete_pos(complete_sources)

    if neocomplete.complete_pos < 0
      call neocomplete#helper#clear_result()

      return -2
    endif

    let neocomplete.complete_sources = complete_sources

    return neocomplete.complete_pos
  endif

  let neocomplete.complete_pos =
        \ neocomplete#complete#_get_complete_pos(
        \     neocomplete.complete_sources)
  let candidates = neocomplete#complete#_get_words(
        \ neocomplete.complete_sources,
        \ neocomplete.complete_pos, a:base)

  let neocomplete.candidates = candidates
  let neocomplete.complete_str = a:base

  return candidates
endfunction"}}}

function! neocomplete#complete#unite_complete(findstart, base) "{{{
  " Dummy.
  return a:findstart ? -1 : []
endfunction"}}}

function! neocomplete#complete#auto_complete(findstart, base) "{{{
  return neocomplete#complete#manual_complete(a:findstart, a:base)
endfunction"}}}

function! neocomplete#complete#_get_results(cur_text, ...) "{{{
  if g:neocomplete_enable_debug
    echomsg 'start get_complete_sources'
  endif

  let neocomplete = neocomplete#get_current_neocomplete()
  let neocomplete.start_time = reltime()

  let complete_sources = call(
        \ 'neocomplete#complete#_set_results_pos', [a:cur_text] + a:000)
  call neocomplete#complete#_set_results_words(complete_sources)

  return filter(copy(complete_sources),
        \ '!empty(v:val.neocomplete__context.candidates)')
endfunction"}}}

function! neocomplete#complete#_get_complete_pos(sources) "{{{
  if empty(a:sources)
    return -1
  endif

  return min([col('.')] + map(copy(a:sources),
        \ 'v:val.neocomplete__context.complete_pos'))
endfunction"}}}

function! neocomplete#complete#_get_words(sources, complete_pos, complete_str) "{{{
  let frequencies = neocomplete#variables#get_frequencies()
  if exists('*neocomplete#sources#buffer_complete#get_frequencies')
    let frequencies = extend(copy(
          \ neocomplete#sources#buffer_complete#get_frequencies()),
          \ frequencies)
  endif

  " Append prefix.
  let candidates = []
  let len_words = 0
  for source in sort(filter(copy(a:sources),
        \ '!empty(v:val.neocomplete__context.candidates)'),
        \  's:compare_source_rank')
    let context = source.neocomplete__context
    let words =
          \ type(context.candidates[0]) == type('') ?
          \ map(copy(context.candidates), "{'word': v:val}") :
          \ deepcopy(context.candidates)
    let context.candidates = words

    call neocomplete#helper#call_hook(
          \ source, 'on_post_filter', {})

    if context.complete_pos > a:complete_pos
      let prefix = a:complete_str[: context.complete_pos
            \                            - a:complete_pos - 1]

      for candidate in words
        let candidate.word = prefix . candidate.word
      endfor
    endif

    for candidate in words
      if !has_key(candidate, 'menu') && has_key(source, 'mark')
        " Set default menu.
        let candidate.menu = source.mark
      endif
      if has_key(frequencies, candidate.word)
        let candidate.rank = frequencies[candidate.word]
      endif
    endfor

    let words = neocomplete#helper#call_filters(
          \ source.sorters, source, {})

    if source.max_candidates > 0
      let words = words[: len(source.max_candidates)-1]
    endif

    let words = neocomplete#helper#call_filters(
          \ source.converters, source, {})

    let candidates += words
    let len_words += len(words)

    if g:neocomplete_max_list > 0
          \ && len_words > g:neocomplete_max_list
      break
    endif

    if neocomplete#complete_check()
      return []
    endif
  endfor

  if g:neocomplete_max_list > 0
    let candidates = candidates[: g:neocomplete_max_list]
  endif

  " Check dup and set icase.
  let icase = g:neocomplete_enable_ignore_case &&
        \!(g:neocomplete_enable_smart_case && a:complete_str =~ '\u')
        \ && !neocomplete#is_text_mode()
  for candidate in candidates
    if has_key(candidate, 'kind') && candidate.kind == ''
      " Remove kind key.
      call remove(candidate, 'kind')
    endif

    let candidate.icase = icase
  endfor

  if neocomplete#complete_check()
    return []
  endif

  return candidates
endfunction"}}}
function! neocomplete#complete#_set_results_pos(cur_text, ...) "{{{
  " Set context filetype.
  call neocomplete#context_filetype#set()

  " Initialize sources.
  let neocomplete = neocomplete#get_current_neocomplete()
  for source in filter(values(neocomplete#variables#get_sources()),
        \ '!v:val.loaded && (empty(v:val.filetypes) ||
        \       get(v:val.filetypes,
        \             neocomplete.context_filetype, 0))')
    call neocomplete#helper#call_hook(source, 'on_init', {})
    let source.loaded = 1
  endfor

  let sources = filter(copy(get(a:000, 0,
        \ neocomplete#helper#get_sources_list())), 'v:val.loaded')
  if a:0 < 1
    call filter(sources, '!neocomplete#is_plugin_locked(v:key)')
  endif

  " Try source completion. "{{{
  let complete_sources = []
  for source in values(sources)
    let context = source.neocomplete__context
    let context.input = a:cur_text

    let pos = winsaveview()

    try
      let complete_pos =
            \ has_key(source, 'get_keyword_pos') ?
            \ source.get_keyword_pos(context.input) :
            \ has_key(source, 'get_complete_position') ?
            \ source.get_complete_position(context) :
            \ neocomplete#match_word(context.input)[0]
    catch
      call neocomplete#print_error(v:throwpoint)
      call neocomplete#print_error(v:exception)
      call neocomplete#print_error(
            \ 'Error occured in source''s get_complete_position()!')
      call neocomplete#print_error(
            \ 'Source name is ' . source.name)
      return complete_sources
    finally
      if winsaveview() != pos
        call winrestview(pos)
      endif
    endtry

    if complete_pos < 0
      let source.neocomplete__context =
            \ neocomplete#init#_context(
            \    source.neocomplete__context)
      continue
    endif

    let complete_str = context.input[complete_pos :]
    if neocomplete#is_auto_complete() &&
          \ neocomplete#util#mb_strlen(complete_str)
          \     < neocomplete#get_completion_length(source.name)
      " Skip.
      let source.neocomplete__context =
            \ neocomplete#init#_context(
            \    source.neocomplete__context)
      continue
    endif

    let context.complete_pos = complete_pos
    let context.complete_str = complete_str
    call add(complete_sources, source)
  endfor
  "}}}

  return complete_sources
endfunction"}}}
function! neocomplete#complete#_set_results_words(sources) "{{{
  " Try source completion.
  for source in a:sources
    if neocomplete#complete_check()
      return
    endif

    " Save options.
    let ignorecase_save = &ignorecase

    let context = source.neocomplete__context

    if neocomplete#is_text_mode()
      let &ignorecase = 1
    elseif g:neocomplete_enable_smart_case
          \ && context.complete_str =~ '\u'
      let &ignorecase = 0
    else
      let &ignorecase = g:neocomplete_enable_ignore_case
    endif

    let pos = winsaveview()

    if !source.is_volatile
          \ && context.prev_complete_pos == context.complete_pos
      " Use previous candidates.
      let context.candidates = context.prev_candidates
    else
      try
        let context.candidates =
              \ has_key(source, 'get_keyword_list') ?
              \   source.get_keyword_list(context.complete_str) :
              \ has_key(source, 'get_complete_words') ?
              \   source.get_complete_words(
              \     context.complete_pos, context.complete_str) :
              \   source.gather_candidates(context)
      catch
        call neocomplete#print_error(v:throwpoint)
        call neocomplete#print_error(v:exception)
        call neocomplete#print_error(
              \ 'Source name is ' . source.name)
        call neocomplete#print_error(
              \ 'Error occured in source''s gather_candidates()!')
        return
      finally
        if winsaveview() != pos
          call winrestview(pos)
        endif
      endtry
    endif

    let context.prev_candidates = copy(context.candidates)
    let context.prev_complete_pos = context.complete_pos

    if has_key(source, 'gather_candidates')
      let context.candidates = neocomplete#helper#call_filters(
            \ source.matchers, source, {})
    endif

    if g:neocomplete_enable_debug
      echomsg source.name
    endif

    let &ignorecase = ignorecase_save
  endfor
endfunction"}}}

" Source rank order. "{{{
function! s:compare_source_rank(i1, i2)
  return a:i2.rank - a:i1.rank
endfunction"}}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: foldmethod=marker
