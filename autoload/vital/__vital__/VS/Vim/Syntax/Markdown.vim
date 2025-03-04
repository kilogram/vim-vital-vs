"
" apply
"
" TODO: Refactor
"
function! s:apply(...) abort
  let l:args = get(a:000, 0, {})
  let l:text = has_key(l:args, 'text') ? l:args.text : getbufline('%', 1, '$')
  let l:text = type(l:text) == v:t_list ? join(l:text, "\n") : l:text

  call s:_execute('syntax sync clear')
  if !exists('b:___VS_Vim_Syntax_Markdown')
    " Avoid automatic highlighting by built-in runtime syntax.
    if !has_key(g:, 'markdown_fenced_languages')
      call s:_execute('runtime! syntax/markdown.vim')
    else
      let l:markdown_fenced_languages = g:markdown_fenced_languages
      unlet g:markdown_fenced_languages
      call s:_execute('runtime! syntax/markdown.vim')
      let g:markdown_fenced_languages = l:markdown_fenced_languages
    endif

    " Remove markdownCodeBlock because we support it manually.
    call s:_clear('markdownCodeBlock') " runtime
    call s:_clear('mkdCode') " plasticboy/vim-markdown

    " Modify markdownCode (`codes...`)
    call s:_clear('markdownCode')
    syntax region markdownCode matchgroup=Conceal start=/\%(``\)\@!`/ matchgroup=Conceal end=/\%(``\)\@!`/ containedin=TOP keepend concealends

    " Modify markdownEscape (_bold\_text_) @see nvim's syntax/lsp_markdown.vim
    call s:_clear('markdownEscape')
    syntax region markdownEscape matchgroup=markdownEscape start=/\\\ze[\\\x60*{}\[\]()#+\-,.!_>~|"$%&'\/:;<=?@^ ]/ end=/./ containedin=ALL keepend oneline concealends

    " Add syntax for basic html entities.
    syntax match vital_vs_vim_syntax_markdown_entities_lt /&lt;/ containedin=ALL conceal cchar=<
    syntax match vital_vs_vim_syntax_markdown_entities_gt /&gt;/ containedin=ALL conceal cchar=>
    syntax match vital_vs_vim_syntax_markdown_entities_amp /&amp;/ containedin=ALL conceal cchar=&
    syntax match vital_vs_vim_syntax_markdown_entities_quot /&quot;/ containedin=ALL conceal cchar="
    syntax match vital_vs_vim_syntax_markdown_entities_nbsp /&nbsp;/ containedin=ALL conceal cchar= 

    let b:___VS_Vim_Syntax_Markdown = {}
    let b:___VS_Vim_Syntax_Markdown.marks = {}
    let b:___VS_Vim_Syntax_Markdown.filetypes = {}
  endif

  for [l:mark, l:filetype] in items(s:_get_filetype_map(l:text))
    try
      let l:mark_group = substitute(toupper(l:mark), '\.', '_', 'g')
      if has_key(b:___VS_Vim_Syntax_Markdown.marks, l:mark_group)
        continue
      endif
      let b:___VS_Vim_Syntax_Markdown.marks[l:mark_group] = v:true

      let l:filetype_group = substitute(toupper(l:filetype), '\.', '_', 'g')
      if !has_key(b:___VS_Vim_Syntax_Markdown.filetypes, l:filetype_group)
        call s:_execute('syntax include @%s syntax/%s.vim', l:filetype_group, l:filetype)
        let b:___VS_Vim_Syntax_Markdown.filetypes[l:filetype_group] = v:true
      endif

      call s:_execute('syntax region %s matchgroup=Conceal start=/%s/ matchgroup=Conceal end=/%s/ contains=@%s containedin=TOP keepend concealends',
      \   l:mark_group,
      \   printf('```\s*%s\s*', l:mark),
      \   '```\s*\%(' . "\n" . '\|$\)',
      \   l:filetype_group
      \ )
    catch /.*/
      unsilent echomsg string({ 'exception': v:exception, 'throwpoint': v:throwpoint })
    endtry
  endfor
endfunction

"
" _clear
"
function! s:_clear(group) abort
  try
    execute printf('silent! syntax clear %s', a:group)
  catch /.*/
  endtry
endfunction

"
"  _execute
"
function! s:_execute(command, ...) abort
  let b:current_syntax = ''
  unlet b:current_syntax

  let g:main_syntax = ''
  unlet g:main_syntax

  execute call('printf', [a:command] + a:000)
endfunction

"
" _get_filetype_map
"
function! s:_get_filetype_map(text) abort
  let l:filetype_map = {}
  for l:mark in s:_find_marks(a:text)
    let l:filetype_map[l:mark] = s:_get_filetype_from_mark(l:mark)
  endfor
  return l:filetype_map
endfunction

"
" _find_marks
"
function! s:_find_marks(text) abort
  let l:marks = {}

  " find from buffer contents.
  let l:text = a:text
  let l:pos = 0
  while 1
    let l:match = matchstrpos(l:text, '```\s*\zs\w\+', l:pos, 1)
    if empty(l:match[0])
      break
    endif
    let l:marks[l:match[0]] = v:true
    let l:pos = l:match[2]
  endwhile

  return keys(l:marks)
endfunction

"
" _get_filetype_from_mark
"
function! s:_get_filetype_from_mark(mark) abort
  for l:config in get(g:, 'markdown_fenced_languages', [])
    if l:config !~# '='
      if l:config ==# a:mark
        return a:mark
      endif
    else
      let l:config = split(l:config, '=')
      if l:config[0] ==# a:mark
        return l:config[1]
      endif
    endif
  endfor
  return a:mark
endfunction

