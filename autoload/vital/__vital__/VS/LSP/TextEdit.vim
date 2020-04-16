"
" _vital_loaded
"
function! s:_vital_loaded(V) abort
  let s:Text = a:V.import('VS.LSP.Text')
  let s:Position = a:V.import('VS.LSP.Position')
endfunction

"
" _vital_depends
"
function! s:_vital_depends() abort
  return ['VS.LSP.Text']
endfunction

"
" fixeol
"
let s:_fixeol = v:false
function! s:fixeol(bool) abort
  let s:_fixeol = a:bool
endfunction

"
" apply
"
function! s:apply(path, text_edits) abort
  let l:current_bufname = bufname('%')
  let l:target_bufname = a:path
  let l:cursor_position = s:Position.cursor()

  call s:_switch(l:target_bufname)
  for l:text_edit in s:_normalize(a:text_edits)
    call s:_apply(bufnr(l:target_bufname), l:text_edit, l:cursor_position)
  endfor
  call s:_switch(l:current_bufname)

  if bufnr(l:current_bufname) == bufnr(l:target_bufname)
    try
      call cursor(s:Position.lsp_to_vim('%', l:cursor_position))
    catch /.*/
      echomsg string({ 'exception': v:exception, 'throwpoint': v:throwpoint })
    endtry
  endif
endfunction

"
" _apply
"
function! s:_apply(bufnr, text_edit, cursor_position) abort
  " create before/after line.
  let l:start_line = getline(a:text_edit.range.start.line + 1)
  let l:end_line = getline(a:text_edit.range.end.line + 1)
  let l:before_line = strcharpart(l:start_line, 0, a:text_edit.range.start.character)
  let l:after_line = strcharpart(l:end_line, a:text_edit.range.end.character, strchars(l:end_line) - a:text_edit.range.end.character)

  " create lines.
  let l:lines = s:Text.split_by_eol(a:text_edit.newText)
  let l:lines[0] = l:before_line . l:lines[0]
  let l:lines[-1] = l:lines[-1] . l:after_line

  " fix eol.
  let l:buf_len = len(getbufline(a:bufnr, '^', '$'))
  let l:fixeol = s:_fixeol
  let l:fixeol = l:fixeol && &fixendofline
  let l:fixeol = l:fixeol && l:lines[-1] ==# ''
  let l:fixeol = l:fixeol && l:buf_len <= a:text_edit.range.end.line
  let l:fixeol = l:fixeol && a:text_edit.range.end.character == 0
  if l:fixeol
    call remove(l:lines, -1)
  endif

  let l:lines_len = len(l:lines)
  let l:range_len = (a:text_edit.range.end.line - a:text_edit.range.start.line) + 1

  " fix cursor
  if a:text_edit.range.end.line <= a:cursor_position.line && a:text_edit.range.end.character <= a:cursor_position.character
    " fix cursor col
    if a:text_edit.range.end.line == a:cursor_position.line
      let l:end_character = strchars(l:lines[-1]) - strchars(l:after_line)
      let l:end_offset = a:cursor_position.character - a:text_edit.range.end.character
      let a:cursor_position.character = l:end_character + l:end_offset
    endif

    " fix cursor line
    let a:cursor_position.line += l:lines_len - l:range_len
  endif

  " append or delete lines.
  if l:lines_len > l:range_len
    call append(a:text_edit.range.start.line, repeat([''], l:lines_len - l:range_len))
  elseif l:lines_len < l:range_len
    let l:offset = l:range_len - l:lines_len
    call s:_delete(a:bufnr, a:text_edit.range.start.line + 1, a:text_edit.range.start.line + l:offset)
  endif

  " set lines.
  call setline(a:text_edit.range.start.line + 1, l:lines)
endfunction

"
" _normalize
"
function! s:_normalize(text_edits) abort
  let l:text_edits = type(a:text_edits) == type([]) ? a:text_edits : [a:text_edits]
  let l:text_edits = s:_range(l:text_edits)
  let l:text_edits = sort(copy(l:text_edits), function('s:_compare', [], {}))
  let l:text_edits = s:_check(l:text_edits)
  return reverse(l:text_edits)
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
        throw 'VS.LSP.TextEdit: range overlapped.'
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
" _delete
"
function! s:_delete(bufnr, start, end) abort
  if exists('*deletebufline')
    call deletebufline(a:bufnr, a:start, a:end)
  else
    let l:foldenable = &foldenable
    setlocal nofoldenable
    execute printf('%s,%sdelete _', a:start, a:end)
    let &foldenable = l:foldenable
  endif
endfunction

