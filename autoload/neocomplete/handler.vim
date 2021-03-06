"=============================================================================
" FILE: handler.vim
" AUTHOR: Shougo Matsushita <Shougo.Matsu@gmail.com>
" Last Modified: 21 Jun 2013.
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

function! neocomplete#handler#_on_moved_i() "{{{
  let neocomplete = neocomplete#get_current_neocomplete()
  if neocomplete.linenr != line('.')
    call neocomplete#helper#clear_result()
  endif
  let neocomplete.linenr = line('.')

  " Get cursor word.
  let cur_text = neocomplete#get_cur_text(1)

  " Make cache.
  if cur_text =~ '^\s*$\|\s\+$'
    if neocomplete#is_enabled_source('buffer')
      " Caching current cache line.
      call neocomplete#sources#buffer#make_cache_current_line()
    endif
    if neocomplete#is_enabled_source('member')
      " Caching current cache line.
      call neocomplete#sources#member#make_cache_current_line()
    endif
  endif

  call s:close_preview_window()
endfunction"}}}
function! neocomplete#handler#_on_insert_enter() "{{{
  let neocomplete = neocomplete#get_current_neocomplete()
  if neocomplete.linenr != line('.')
    call neocomplete#helper#clear_result()
  endif
  let neocomplete.linenr = line('.')

  if &l:foldmethod ==# 'expr' && foldlevel('.') != 0
    foldopen
  endif
endfunction"}}}
function! neocomplete#handler#_on_insert_leave() "{{{
  call neocomplete#helper#clear_result()

  call s:close_preview_window()
endfunction"}}}
function! neocomplete#handler#_on_write_post() "{{{
  let neocomplete = neocomplete#get_current_neocomplete()

  " Restore foldinfo.
  for winnr in filter(range(1, winnr('$')),
        \ "!empty(getwinvar(v:val, 'neocomplete_foldinfo'))")
    let neocomplete_foldinfo =
          \ getwinvar(winnr, 'neocomplete_foldinfo')
    call setwinvar(winnr, '&foldmethod',
          \ neocomplete_foldinfo.foldmethod)
    call setwinvar(winnr, '&foldexpr',
          \ neocomplete_foldinfo.foldexpr)
    call setwinvar(winnr,
          \ 'neocomplete_foldinfo', {})
  endfor
endfunction"}}}
function! neocomplete#handler#_on_complete_done() "{{{
  " Get cursor word.
  let [_, candidate] = neocomplete#match_word(
        \ neocomplete#get_cur_text(1))
  if candidate == ''
    return
  endif

  let frequencies = neocomplete#variables#get_frequencies()
  if !has_key(frequencies, candidate)
    let frequencies[candidate] = 20
  else
    let frequencies[candidate] += 20
  endif
endfunction"}}}
function! neocomplete#handler#_change_update_time() "{{{
  if &updatetime > g:neocomplete#cursor_hold_i_time
    " Change updatetime.
    let neocomplete = neocomplete#get_current_neocomplete()
    let neocomplete.update_time_save = &updatetime
    let &updatetime = g:neocomplete#cursor_hold_i_time
  endif
endfunction"}}}
function! neocomplete#handler#_restore_update_time() "{{{
  let neocomplete = neocomplete#get_current_neocomplete()
  if &updatetime < neocomplete.update_time_save
    " Restore updatetime.
    let &updatetime = neocomplete.update_time_save
  endif
endfunction"}}}

function! neocomplete#handler#_do_auto_complete(event) "{{{
  if s:check_in_do_auto_complete()
    return
  endif

  let neocomplete = neocomplete#get_current_neocomplete()
  let neocomplete.skipped = 0
  let neocomplete.event = a:event

  let cur_text = neocomplete#get_cur_text(1)

  if g:neocomplete#enable_debug
    echomsg 'cur_text = ' . cur_text
  endif

  " Prevent infinity loop.
  if s:is_skip_auto_complete(cur_text)
    if g:neocomplete#enable_debug
      echomsg 'Skipped.'
    endif
    return
  endif

  let neocomplete.old_cur_text = cur_text

  if neocomplete#helper#is_omni(cur_text)
    call feedkeys("\<C-x>\<C-o>\<C-p>", 'n')
    return
  endif

  " Check multibyte input or eskk.
  if neocomplete#is_eskk_enabled()
        \ || neocomplete#is_multibyte_input(cur_text)
    if g:neocomplete#enable_debug
      echomsg 'Skipped.'
    endif

    return
  endif

  " Check complete position.
  let complete_sources = neocomplete#complete#_set_results_pos(cur_text)
  if empty(complete_sources)
    if g:neocomplete#enable_debug
      echomsg 'Skipped.'
    endif

    return
  endif

  let &l:completefunc = 'neocomplete#complete#auto_complete'

  if neocomplete#is_prefetch()
    " Do prefetch.
    let neocomplete.complete_sources =
          \ neocomplete#complete#_get_results(cur_text)

    if empty(neocomplete.complete_sources)
      if g:neocomplete#enable_debug
        echomsg 'Skipped.'
      endif
      return
    endif
  endif

  call s:save_foldinfo()

  set completeopt-=menu
  set completeopt-=longest
  set completeopt+=menuone

  " Set options.
  let neocomplete.completeopt = &completeopt

  if neocomplete#util#is_complete_select()
    if g:neocomplete#enable_auto_select
      set completeopt-=noselect
      set completeopt+=noinsert
    else
      set completeopt+=noinsert,noselect
    endif
  endif

  " Start auto complete.
  call feedkeys("\<Plug>(neocomplete_start_auto_complete)")
endfunction"}}}

function! s:save_foldinfo() "{{{
  " Save foldinfo.
  let winnrs = filter(range(1, winnr('$')),
        \ "winbufnr(v:val) == bufnr('%')")

  " Note: for foldmethod=expr or syntax.
  call filter(winnrs, "
        \  (getwinvar(v:val, '&foldmethod') ==# 'expr' ||
        \   getwinvar(v:val, '&foldmethod') ==# 'syntax') &&
        \  getwinvar(v:val, '&modifiable')")
  for winnr in winnrs
    call setwinvar(winnr, 'neocomplete_foldinfo', {
          \ 'foldmethod' : getwinvar(winnr, '&foldmethod'),
          \ 'foldexpr'   : getwinvar(winnr, '&foldexpr')
          \ })
    call setwinvar(winnr, '&foldmethod', 'manual')
    call setwinvar(winnr, '&foldexpr', 0)
  endfor
endfunction"}}}
function! s:check_in_do_auto_complete() "{{{
  if neocomplete#is_locked()
    return 1
  endif

  " Detect completefunc.
  if &l:completefunc !~# '^neocomplete#'
    if g:neocomplete#force_overwrite_completefunc
      " Set completefunc.
      let &l:completefunc = 'neocomplete#complete#manual_complete'
    else
      " Warning.
      redir => output
      99verbose setl completefunc
      redir END
      call neocomplete#print_error(output)
      call neocomplete#print_error(
            \ 'Another plugin set completefunc! Disabled neocomplete.')
      NeoCompleteLock
      return 1
    endif
  endif

  " Detect AutoComplPop.
  if exists('g:acp_enableAtStartup') && g:acp_enableAtStartup
    call neocomplete#print_error(
          \ 'Detected enabled AutoComplPop! Disabled neocomplete.')
    NeoCompleteLock
    return 1
  endif
endfunction"}}}
function! s:is_skip_auto_complete(cur_text) "{{{
  let neocomplete = neocomplete#get_current_neocomplete()

  if a:cur_text =~ '^\s*$\|\s\+$'
        \ || a:cur_text == neocomplete.old_cur_text
        \ || (g:neocomplete#lock_iminsert && &l:iminsert)
        \ || (&l:formatoptions =~# '[tc]' && &l:textwidth > 0
        \     && neocomplete#util#wcswidth(a:cur_text) >= &l:textwidth)
    return 1
  endif

  if !neocomplete.skip_next_complete
    return 0
  endif

  " Check delimiter pattern.
  let is_delimiter = 0
  let filetype = neocomplete#get_context_filetype()

  for delimiter in ['/', '\.'] +
        \ get(g:neocomplete#delimiter_patterns, filetype, [])
    if a:cur_text =~ delimiter . '$'
      let is_delimiter = 1
      break
    endif
  endfor

  if is_delimiter && neocomplete.skip_next_complete == 2
    let neocomplete.skip_next_complete = 0
    return 0
  endif

  let neocomplete.skip_next_complete = 0
  let neocomplete.cur_text = ''
  let neocomplete.old_cur_text = ''

  return 1
endfunction"}}}
function! s:close_preview_window() "{{{
  if g:neocomplete#enable_auto_close_preview &&
        \ bufname('%') !=# '[Command Line]' && winnr('$') != 1
    " Close preview window.
    pclose!
  endif
endfunction"}}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: foldmethod=marker
