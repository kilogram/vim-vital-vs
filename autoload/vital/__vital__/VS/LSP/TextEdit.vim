"
" _vital_loaded
"
function! s:_vital_loaded(V) abort
  let s:Text = a:V.import('VS.LSP.Text')
  let s:Position = a:V.import('VS.LSP.Position')
  let s:Option = a:V.import('VS.Vim.Option')
endfunction

"
" _vital_depends
"
function! s:_vital_depends() abort
  return ['VS.LSP.Text', 'VS.LSP.Position', 'VS.Vim.Option']
endfunction

"
" Current selected method.
"
let s:_method = 'auto'

"
" This dict contains some logics for patching text.
"
let s:_methods = {}

"
" set_method
"
function! s:set_method(method) abort
  if !has_key(s:_methods, a:method)
    let s:_method = 'auto'
  elseif a:method ==# 'nvim_buf_set_text' && !exists('*nvim_buf_set_text')
    let s:_method = 'auto'
  elseif a:method ==# 'normal' && has('nvim')
    let s:_method = 'auto'
  else
    let s:_method = a:method
  endif
endfunction

"
" get_method
"
function! s:get_method() abort
  if s:_method ==# 'auto'
    if exists('*nvim_buf_set_text')
      return 'nvim_buf_set_text'
    else
      return 'normal'
    endif
  endif
  return s:_method
endfunction

"
" get_methods
"
function! s:get_methods() abort
  return ['nvim_buf_set_text', 'normal', 'function']
endfunction

"
" is_text_mark_preserved
"
function! s:is_text_mark_preserved() abort
  return index(['nvim_buf_set_text'], s:get_method()) >= 0
endfunction

"
" apply
"
function! s:apply(path, text_edits) abort
  let l:current_bufname = bufname('%')
  let l:target_bufname = a:path
  let l:cursor_position = s:Position.cursor()

  try
    call s:_switch(a:path)
    let [l:has_overflowed, l:text_edits] = s:_normalize(bufnr(l:target_bufname), a:text_edits)
    let l:fix_cursor = s:_methods[s:get_method()](bufnr(l:target_bufname), l:text_edits, l:cursor_position)
    if l:has_overflowed && getline('$') ==# ''
      call s:delete(bufnr(l:target_bufname), '$', '$')
    endif
    call s:_switch(l:current_bufname)
  catch /.*/
    call themis#log(string({ 'exception': v:exception, 'throwpoint': v:throwpoint }))
  endtry

  if get(l:, 'fix_cursor', v:false) && bufnr(l:current_bufname) == bufnr(l:target_bufname)
    call cursor(s:Position.lsp_to_vim('%', l:cursor_position))
  endif
endfunction

let s:_methods = {}

"
" nvim_buf_set_text
"
function! s:_methods.nvim_buf_set_text(bufnr, text_edits, cursor_position) abort
  let l:fix_cursor = v:false

  for l:text_edit in a:text_edits
    let l:start = s:Position.lsp_to_vim(a:bufnr, l:text_edit.range.start)
    let l:end = s:Position.lsp_to_vim(a:bufnr, l:text_edit.range.end)
    let l:lines = s:Text.split_by_eol(l:text_edit.newText)
    call nvim_buf_set_text(
    \   a:bufnr,
    \   l:start[0] - 1,
    \   l:start[1] - 1,
    \   l:end[0] - 1,
    \   l:end[1] - 1,
    \   l:lines
    \ )
    let l:fix_cursor = s:_fix_cursor(a:cursor_position, l:text_edit, l:lines) || l:fix_cursor
  endfor

  return l:fix_cursor
endfunction

"
" normal
"
function! s:_methods.normal(bufnr, text_edits, cursor_position) abort
  let l:fix_cursor = v:false

  try
    let l:Restore = s:Option.define({
    \   'foldenable': '0',
    \   'virtualedit': 'onemore',
    \   'whichwrap': 'h',
    \   'selection': 'exclusive',
    \ })
    let l:view = winsaveview()
    let l:regx = getreg('x')

    for l:text_edit in a:text_edits
      let l:start = s:Position.lsp_to_vim(a:bufnr, l:text_edit.range.start)
      let l:end = s:Position.lsp_to_vim(a:bufnr, l:text_edit.range.end)
      if l:start[0] != l:end[0] || l:start[1] != l:end[1]
        let l:command = printf('%sG%s|v%sG%s|"_d', l:start[0], l:start[1], l:end[0], l:end[1])
      else
        let l:command = printf('%sG%s|', l:start[0], l:start[1])
      endif
      call setreg('x', s:Text.normalize_eol(l:text_edit.newText), 'c')
      execute printf('noautocmd keepjumps normal! %s"xP', l:command)

      let l:fix_cursor = s:_fix_cursor(a:cursor_position, l:text_edit, s:Text.split_by_eol(l:text_edit.newText)) || l:fix_cursor
    endfor
  catch /.*/
    echomsg string({ 'exception': v:exception, 'throwpoint': v:throwpoint })
  finally
    call l:Restore()
    call winrestview(l:view)
    call setreg('x', l:regx)
  endtry

  return l:fix_cursor
endfunction

"
" function
"
function! s:_methods.function(bufnr, text_edits, cursor_position) abort
  let l:fix_cursor = v:false

  for l:text_edit in a:text_edits
    let l:start_line = getline(l:text_edit.range.start.line + 1)
    let l:end_line = getline(l:text_edit.range.end.line + 1)
    let l:before_line = strcharpart(l:start_line, 0, l:text_edit.range.start.character)
    let l:after_line = strcharpart(l:end_line, l:text_edit.range.end.character, strchars(l:end_line) - l:text_edit.range.end.character)

    " create lines.
    let l:lines = s:Text.split_by_eol(l:text_edit.newText)
    let l:lines[0] = l:before_line . l:lines[0]
    let l:lines[-1] = l:lines[-1] . l:after_line

    " save length.
    let l:lines_len = len(l:lines)
    let l:range_len = (l:text_edit.range.end.line - l:text_edit.range.start.line) + 1

    " append or delete lines.
    if l:lines_len > l:range_len
      call append(l:text_edit.range.end.line, repeat([''], l:lines_len - l:range_len))
    elseif l:lines_len < l:range_len
      call s:delete(a:bufnr, l:text_edit.range.start.line + l:lines_len, l:text_edit.range.end.line)
    endif

    " set lines.
    let l:i = 0
    while l:i < len(l:lines)
      let l:lnum = l:text_edit.range.start.line + l:i + 1
      if get(getbufline(a:bufnr, l:lnum), 0, v:null) !=# l:lines[l:i]
        call setline(l:lnum, l:lines[l:i])
      endif
      let l:i += 1
    endwhile

    let l:fix_cursor = s:_fix_cursor(a:cursor_position, l:text_edit, s:Text.split_by_eol(l:text_edit.newText))
  endfor

  return l:fix_cursor
endfunction

"
" _fix_cursor
"
function! s:_fix_cursor(position, text_edit, lines) abort
  let l:lines_len = len(a:lines)
  let l:range_len = (a:text_edit.range.end.line - a:text_edit.range.start.line) + 1

  if a:text_edit.range.end.line < a:position.line
    let a:position.line += l:lines_len - l:range_len
    return v:true
  elseif a:text_edit.range.end.line == a:position.line && a:text_edit.range.end.character <= a:position.character
    let a:position.line += l:lines_len - l:range_len
    let a:position.character = strchars(a:lines[-1]) + (a:position.character - a:text_edit.range.end.character)
    if l:lines_len == 1
      let a:position.character += a:text_edit.range.start.character
    endif
    return v:true
  endif
  return v:false
endfunction

"
" _normalize
"
function! s:_normalize(bufnr, text_edits) abort
  let l:text_edits = type(a:text_edits) == type([]) ? a:text_edits : [a:text_edits]
  let l:text_edits = s:_range(l:text_edits)
  let l:text_edits = sort(copy(l:text_edits), function('s:_compare', [], {}))
  let l:text_edits = s:_check(l:text_edits)
  let l:text_edits =  reverse(l:text_edits)
  return s:_fix_text_edits(a:bufnr, l:text_edits)
endfunction

"
" _range
"
function! s:_range(text_edits) abort
  for l:text_edit in a:text_edits
    if l:text_edit.range.start.line > l:text_edit.range.end.line || (
    \   l:text_edit.range.start.line == l:text_edit.range.end.line &&
    \   l:text_edit.range.start.character > l:text_edit.range.end.character
    \ )
      let l:text_edit.range = { 'start': l:text_edit.range.end, 'end': l:text_edit.range.start }
    endif
  endfor
  return a:text_edits
endfunction

"
" _check
"
function! s:_check(text_edits) abort
  if len(a:text_edits) > 1
    let l:range = a:text_edits[0].range
    for l:text_edit in a:text_edits[1 : -1]
      if l:range.end.line > l:text_edit.range.start.line || (
      \   l:range.end.line == l:text_edit.range.start.line &&
      \   l:range.end.character > l:text_edit.range.start.character
      \ )
        echomsg 'VS.LSP.TextEdit: range overlapped.'
      endif
      let l:range = l:text_edit.range
    endfor
  endif
  return a:text_edits
endfunction

"
" _compare
"
function! s:_compare(text_edit1, text_edit2) abort
  let l:diff = a:text_edit1.range.start.line - a:text_edit2.range.start.line
  if l:diff == 0
    return a:text_edit1.range.start.character - a:text_edit2.range.start.character
  endif
  return l:diff
endfunction

"
" _fix_text_edits
"
function! s:_fix_text_edits(bufnr, text_edits) abort
  let l:buf = getbufline(a:bufnr, '^', '$')
  let l:max = len(l:buf)

  let l:has_overflowed = v:false
  let l:text_edits = []
  for l:text_edit in a:text_edits
    if l:max <= l:text_edit.range.start.line
      let l:text_edit.range.start.line = l:max - 1
      let l:text_edit.range.start.character = strchars(get(l:buf, -1, 0))
      let l:text_edit.newText = "\n" . l:text_edit.newText
      let l:has_overflowed = v:true
    endif
    if l:max <= l:text_edit.range.end.line
      let l:text_edit.range.end.line = l:max - 1
      let l:text_edit.range.end.character = strchars(get(l:buf, -1, 0))
      let l:has_overflowed = v:true
    endif
    call add(l:text_edits, l:text_edit)
  endfor

  return [l:has_overflowed, l:text_edits]
endfunction

"
" _switch
"
function! s:_switch(path) abort
  if bufnr(a:path) >= 0
    execute printf('keepalt keepjumps %sbuffer!', bufnr(a:path))
  else
    execute printf('keepalt keepjumps edit! %s', fnameescape(a:path))
  endif
endfunction

"
" delete
"
function! s:delete(bufnr, start, end) abort
  if exists('*deletebufline')
    call deletebufline(a:bufnr, a:start, a:end)
  else
    try
      let l:Restore = s:Option.define({ 'foldenable': '0' })
      execute printf('%s,%sdelete _', a:start, a:end)
    finally
      call l:Restore()
    endtry
  endif
endfunction
