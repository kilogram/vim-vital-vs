let s:Do = { -> {} }

"
" do
"
function! s:do(winid, func) abort
  let l:curr_winid = win_getid()
  if l:curr_winid == a:winid
    call a:func()
    return
  endif

  if exists('*win_execute')
    let s:Do = a:func
    try
      noautocmd keepalt keepjumps call win_execute(a:winid, 'call s:Do()')
    catch /.*/
      echomsg string({ 'exception': v:exception, 'throwpoint': v:throwpoint })
    endtry
    unlet s:Do
    return
  endif

  noautocmd keepalt keepjumps call win_gotoid(a:winid)
  try
    call a:func()
  catch /.*/
    echomsg string({ 'exception': v:exception, 'throwpoint': v:throwpoint })
  endtry
  noautocmd keepalt keepjumps call win_gotoid(l:curr_winid)
endfunction

"
" screenpos
"
function! s:screenpos(pos) abort
  let l:pos = getpos('.')
  let l:scroll_x = (l:pos[2] + l:pos[3]) - wincol()
  let l:scroll_y = l:pos[1] - winline()
  let l:winpos = win_screenpos(win_getid())
  return [l:winpos[0] + (a:pos[0] - l:scroll_y) - 2, l:winpos[1] + (a:pos[1] - l:scroll_x) - 2]
endfunction

