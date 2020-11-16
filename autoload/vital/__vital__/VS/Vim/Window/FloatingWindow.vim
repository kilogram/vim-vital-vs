"
" _vital_loaded
"
function! s:_vital_loaded(V) abort
  let s:Window = a:V.import('VS.Vim.Window')
  let s:Markdown = a:V.import('VS.Vim.Syntax.Markdown')
endfunction

"
" _vital_depends
"
function! s:_vital_depends() abort
  return ['VS.Vim.Window', 'VS.Vim.Syntax.Markdown']
endfunction

let s:id = 0

"
" new
"
function! s:new() abort
  return s:FloatingWindow.new()
endfunction

let s:FloatingWindow = {}

"
" new
"
function! s:FloatingWindow.new() abort
  let s:id += 1

  let l:buf = bufnr(printf('VS.Vim.Window.FloatingWindow-%s', s:id), v:true)
  call setbufvar(l:buf, '&buflisted', 0)
  call setbufvar(l:buf, '&modeline', 0)
  call setbufvar(l:buf, '&buftype', 'nofile')

  return extend(deepcopy(s:FloatingWindow), {
  \   'id': s:id,
  \   'buf': l:buf,
  \   'win': v:null,
  \ })
endfunction

"
" open
"
" @param {number} args.row
" @param {number} args.col
" @param {string} args.filetype
" @param {string[]} args.contents
" @param {number?} args.maxwidth
" @param {number?} args.minwidth
" @param {number?} args.maxheight
" @param {number?} args.minheight
"
function! s:FloatingWindow.open(args) abort
  let l:size = self.get_size(a:args)
  let l:style = {
    \   'row': a:args.row,
    \   'col': a:args.col,
    \   'width': l:size.width,
    \   'height': l:size.height,
    \ }

  if self.is_visible()
    call s:_move(self.win, l:style)
  else
    let self.win = s:_open(self.buf, l:style)
    call setwinvar(self.win, '&conceallevel', 3)
  endif

  call self.set_contents(a:args.filetype, a:args.contents)
endfunction

"
" close
"
function! s:FloatingWindow.close() abort
  if self.is_visible()
    call s:_close(self.win)
  endif
endfunction

"
" enter
"
function! s:FloatingWindow.enter() abort
  call s:_enter(self.win)
endfunction

"
" is_visible
"
function! s:FloatingWindow.is_visible() abort
  return s:_exists(self.win)
endfunction

"
" get_size
"
function! s:FloatingWindow.get_size(args) abort
  let l:maxwidth = get(a:args, 'maxwidth', -1)
  let l:minwidth = get(a:args, 'minwidth', -1)
  let l:maxheight = get(a:args, 'maxheight', -1)
  let l:minheight = get(a:args, 'minheight', -1)

  " width
  let l:width = 0
  for l:content in a:args.contents
    let l:width = max([l:width, strdisplaywidth(l:content)])
  endfor
  let l:width = l:minwidth == -1 ? l:width : max([l:minwidth, l:width])
  let l:width = l:maxwidth == -1 ? l:width : min([l:maxwidth, l:width])

  " height
  let l:height = len(a:args.contents)
  for l:content in a:args.contents
    let l:wrap = float2nr(ceil(strdisplaywidth(l:content) / str2float('' . l:width)))
    if l:wrap > 1
      let l:height += l:wrap - 1
    endif
  endfor
  let l:height = l:minheight == -1 ? l:height : max([l:minheight, l:height])
  let l:height = l:maxheight == -1 ? l:height : min([l:maxheight, l:height])

  return {
  \   'width': max([1, l:width]),
  \   'height': max([1, l:height]),
  \ }
endfunction

"
" set_contents
"
function! s:FloatingWindow.set_contents(filetype, contents) abort
  call deletebufline(self.buf, '^', '$')
  call setbufline(self.buf, 1, a:contents)

  if a:filetype ==# 'markdown'
    call s:Window.do(self.win, { -> s:Markdown.apply(join(a:contents, "\n")) })
  else
    call setbufvar(self.buf, '&filetype', a:filetype)
  endif
endfunction

"
" open
"
if has('nvim')
  function! s:_open(buf, style) abort
    return nvim_open_win(a:buf, v:false, s:_style(a:style))
  endfunction
else
  function! s:_open(buf, style) abort
    return popup_create(a:buf, s:_style(a:style))
  endfunction
endif

"
" close
"
if has('nvim')
  function! s:_close(win) abort
    call nvim_win_close(a:win, v:true)
  endfunction
else
  function! s:_close(win) abort
    call popup_hide(a:win)
  endfunction
endif

"
" move
"
if has('nvim')
  function! s:_move(win, style) abort
    call nvim_win_set_config(a:win, s:_style(a:style))
  endfunction
else
  function! s:_move(win, style) abort
    call popup_move(a:win, s:_style(a:style))
  endfunction
endif

"
" enter
"
if has('nvim')
  function! s:_enter(win) abort
    call win_gotoid(a:win)
  endfunction
else
  function! s:_enter(win) abort
    " not supported.
  endfunction
endif

"
" exists
"
if has('nvim')
  function! s:_exists(win) abort
    return type(a:win) == type(0) && nvim_win_is_valid(a:win) && nvim_win_get_number(a:win) != -1
  endfunction
else
  function! s:_exists(win) abort
    return type(a:win) == type(0) && win_id2win(a:win) != -1
  endfunction
endif

"
" style
"
if has('nvim')
  function! s:_style(style) abort
    return {
    \   'relative': 'editor',
    \   'width': a:style.width,
    \   'height': a:style.height,
    \   'row': a:style.row,
    \   'col': a:style.col,
    \   'focusable': v:true,
    \   'style': 'minimal',
    \ }
  endfunction
else
  function! s:_style(style) abort
    return {
    \   'line': a:style.row + 1,
    \   'col': a:style.col + 1,
    \   'pos': 'topleft',
    \   'moved': [0, 0, 0],
    \   'scrollbar': 0,
    \   'maxwidth': a:style.width,
    \   'maxheight': a:style.height,
    \   'minwidth': a:style.width,
    \   'minheight': a:style.height,
    \   'tabpage': 0,
    \ }
  endfunction
endif

