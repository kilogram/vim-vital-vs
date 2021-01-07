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
" apply
"
function! s:apply(path, text_edits) abort
  let l:current_bufname = bufname('%')
  let l:current_position = s:Position.cursor()

  let l:target_bufnr = s:_switch(a:path)
  try
    let l:fix_cursor = s:_substitute(l:target_bufnr, a:text_edits, l:current_position)
  catch /.*/
    echomsg string({ 'exception': v:exception, 'throwpoint': v:throwpoint })
  endtry
  let l:current_bufnr = s:_switch(l:current_bufname)

  if get(l:, 'fix_cursor', v:false) && l:current_bufnr == l:target_bufnr
    call cursor(s:Position.lsp_to_vim('%', l:current_position))
  endif
endfunction

"
" _substitute
"
function! s:_substitute(bufnr, text_edits, current_position) abort
  let l:fix_cursor = v:false

  try
    " Save state.
    let l:Restore = s:Option.define({
    \   'foldenable': '0',
    \ })
    let l:view = winsaveview()
    let l:regx = getreg('x')

    " Apply substitute.
    let [l:fixeol, l:text_edits] = s:_normalize(a:bufnr, a:text_edits)
    for l:text_edit in l:text_edits
      let l:start = s:Position.lsp_to_vim(a:bufnr, l:text_edit.range.start)
      let l:end = s:Position.lsp_to_vim(a:bufnr, l:text_edit.range.end)
      call setreg('x', s:Text.normalize_eol(l:text_edit.newText), 'c')
      execute printf('noautocmd keeppatterns keepjumps silent %ssubstitute/\%%%sl\%%%sc\zs\_.\{-}\ze\%%%sl\%%%sc/\=getreg("x")/%se',
      \   l:start[0],
      \   l:start[0],
      \   l:start[1],
      \   l:end[0],
      \   l:end[1],
      \   &gdefault ? 'g' : ''
      \ )
      let l:fix_cursor = s:_fix_cursor(a:current_position, l:text_edit, getreg('x', 1, v:true)) || l:fix_cursor
    endfor

    " Remove last empty line if fixeol enabled.
    if l:fixeol && getline('$') == ''
      $delete _
    endif
  catch /.*/
    echomsg string({ 'exception': v:exception, 'throwpoint': v:throwpoint })
  finally
    " Restore state.
    call l:Restore()
    call winrestview(l:view)
    call setreg('x', l:regx)
  endtry

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
  let l:text_edits = sort(l:text_edits, function('s:_compare'))
  let l:text_edits = s:_check(l:text_edits)
  let l:text_edits =  reverse(l:text_edits)
  return s:_fix_text_edits(a:bufnr, l:text_edits)
endfunction

"
" _range
"
function! s:_range(text_edits) abort
  let l:text_edits = []
  for l:text_edit in a:text_edits
    if type(l:text_edit) != type({})
      continue
    endif
    if l:text_edit.range.start.line > l:text_edit.range.end.line || (
    \   l:text_edit.range.start.line == l:text_edit.range.end.line &&
    \   l:text_edit.range.start.character > l:text_edit.range.end.character
    \ )
      let l:text_edit.range = { 'start': l:text_edit.range.end, 'end': l:text_edit.range.start }
    endif
    let l:text_edits += [l:text_edit]
  endfor
  return l:text_edits
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

  let l:fixeol = v:false
  let l:text_edits = []
  for l:text_edit in a:text_edits
    if l:max <= l:text_edit.range.start.line
      let l:text_edit.range.start.line = l:max - 1
      let l:text_edit.range.start.character = strchars(get(l:buf, -1, 0))
      let l:text_edit.newText = "\n" . l:text_edit.newText
      let l:fixeol = &fixendofline && !&binary
    endif
    if l:max <= l:text_edit.range.end.line
      let l:text_edit.range.end.line = l:max - 1
      let l:text_edit.range.end.character = strchars(get(l:buf, -1, 0))
      let l:fixeol = &fixendofline && !&binary
    endif
    call add(l:text_edits, l:text_edit)
  endfor

  return [l:fixeol, l:text_edits]
endfunction

"
" _switch
"
function! s:_switch(path) abort
  if bufnr(a:path) >= 0
    execute printf('noautocmd keepalt keepjumps %sbuffer!', bufnr(a:path))
  else
    execute printf('noautocmd keepalt keepjumps edit! %s', fnameescape(a:path))
  endif
  return bufnr('%')
endfunction

