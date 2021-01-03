"
" _vital_loaded
"
function! s:_vital_loaded(V) abort
  let s:Position = a:V.import('VS.LSP.Position')
endfunction

"
" _vital_depends
"
function! s:_vital_depends() abort
  return ['VS.LSP.Position']
endfunction

let s:nvim_namespace = {}
let s:vim_prop_types = {}

"
" @param {number} bufnr
" @param {string} id
" @param {array} marks
" @param {VS.LSP.Range} marks[0].range
" @param {string?} marks[0].highlight
"
function! s:set(bufnr, id, marks) abort
  call s:_set(a:bufnr, a:id, a:marks)
endfunction

if has('nvim')
  function! s:_set(bufnr, id, marks) abort
    if !has_key(s:nvim_namespace, a:id)
      let s:nvim_namespace[a:id] = nvim_create_namespace(a:id)
    endif
    for l:mark in a:marks
      let l:start = s:Position.lsp_to_vim(a:bufnr, l:mark.range.start)
      let l:end = s:Position.lsp_to_vim(a:bufnr, l:mark.range.end)
      let l:opts = {
      \   'end_line': l:end[0] - 1,
      \   'end_col': l:end[1] - 1,
      \ }
      if has_key(l:mark, 'highlight')
        let l:opts.hl_group = l:mark.highlight
      endif
      call nvim_buf_set_extmark(
      \   a:bufnr,
      \   s:nvim_namespace[a:id],
      \   l:start[0] - 1,
      \   l:start[1] - 1,
      \   l:opts
      \ )
    endfor
  endfunction
else
  function! s:_set(bufnr, id, marks) abort
    for l:mark in a:marks
      let l:type = s:_create_prop_type_name(l:mark)
      if !has_key(s:vim_prop_types, l:type)
        let s:vim_prop_types[l:type] = s:_create_prop_type_dict(l:mark)
        call prop_type_add(l:type, s:vim_prop_types[l:type])
      endif
      let l:start = s:Position.lsp_to_vim(a:bufnr, l:mark.range.start)
      let l:end = s:Position.lsp_to_vim(a:bufnr, l:mark.range.end)
      call prop_add(l:start[0], l:start[1], {
      \   'id': a:id,
      \   'bufnr': a:bufnr,
      \   'end_lnum': l:end[0],
      \   'end_col': l:end[1],
      \   'type': l:type,
      \ })
    endfor
  endfunction
endif

function! s:_create_prop_type_name(mark) abort
  return printf('VS.Vim.Buffer.TextMark: %s',
  \   get(a:mark, 'highlight', '')
  \ )
endfunction

function! s:_create_prop_type_dict(mark) abort
  let l:type = {
  \   'start_incl': v:true,
  \   'end_incl': v:true,
  \ }
  if has_key(a:mark, 'highlight')
    let l:type.highlight = a:mark.highlight
  endif
  return l:type
endfunction

"
" get
"
" @param {number} bufnr
" @param {string} id
" @returns {array}
"
function! s:get(bufnr, id) abort
  return s:_get(a:bufnr, a:id)
endfunction

if has('nvim')
  function! s:_get(bufnr, id) abort
    if !has_key(s:nvim_namespace, a:id)
      return []
    endif

    let l:extmarks = nvim_buf_get_extmarks(a:bufnr, s:nvim_namespace[a:id], 0, -1, { 'details': v:true })
    return map(l:extmarks, { _, mark -> {
    \   'range': {
    \     'start': s:Position.vim_to_lsp(a:bufnr, [mark[1] + 1, mark[2] + 1]),
    \     'end': s:Position.vim_to_lsp(a:bufnr, [mark[3].end_row + 1, mark[3].end_col + 1])
    \   },
    \   'highlight': get(mark[3], 'hl_group', '')
    \ } })
  endfunction
else
  function! s:_get(bufnr, id) abort
    let l:props = []

    let l:prev_prop = {}
    let l:end_lnum = 1
    let l:end_col = 0
    while 1
      let l:prop = prop_find({ 'bufnr': a:bufnr, 'id': a:id, 'lnum': l:end_lnum, 'col': l:end_col + 1 }, 'f')
      if empty(l:prop) || l:prev_prop == l:prop
        break
      endif
      let l:start = s:Position.vim_to_lsp(a:bufnr, [l:prop.lnum, l:prop.col])
      let l:end_byte = line2byte(l:prop.lnum) + l:prop.col + l:prop.length - 1
      let l:end_lnum = byte2line(l:end_byte)
      let l:end_col = (l:end_byte - line2byte(l:end_lnum)) + 1
      let l:end = s:Position.vim_to_lsp(a:bufnr, [l:end_lnum, l:end_col])

      if has_key(s:vim_prop_types, l:prop.type)
        let l:_prop = {
        \   'range': {
        \     'start': l:start,
        \     'end': l:end,
        \   }
        \ }
        if has_key(s:vim_prop_types[l:prop.type], 'highlight')
          let l:_prop.highlight = s:vim_prop_types[l:prop.type].highlight
        endif
        call add(l:props, l:_prop)
      endif
      let l:prev_prop = l:prop
    endwhile
    return l:props
  endfunction
endif

"
" clear
"
" @param {number} bufnr
" @param {string} id
"
function! s:clear(bufnr, id) abort
  return s:_clear(a:bufnr, a:id)
endfunction

if has('nvim')
  function! s:_clear(bufnr, id) abort
    if !has_key(s:nvim_namespace, a:id)
      return
    endif
    call nvim_buf_clear_namespace(a:bufnr, s:nvim_namespace[a:id], 0, -1)
  endfunction
else
  function! s:_clear(bufnr, id) abort
    call prop_remove({ 'bufnr': a:bufnr, 'id': a:id, 'all': v:true })
  endfunction
endif

