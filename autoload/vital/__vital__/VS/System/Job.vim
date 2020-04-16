"
" _vital_loaded
"
function! s:_vital_loaded(V) abort
  let s:Emitter = a:V.import('VS.Event.Emitter')
endfunction

"
" _vital_depends
"
function! s:_vital_depends() abort
  return ['VS.Event.Emitter']
endfunction

"
" new
"
function! s:new(args) abort
  if has('nvim')
    return s:Nvim.new(a:args)
  else
    return s:Vim.new(a:args)
  endif
endfunction

"
" Nvim
"
let s:Nvim = {}

"
" new
"
function! s:Nvim.new(args) abort
  return extend(deepcopy(s:Nvim), {
  \   'running': v:false,
  \   'command': a:args.command,
  \   'emitter': s:Emitter.new(),
  \   'job': v:null,
  \ })
endfunction

"
" start
"
function! s:Nvim.start(...) abort
  let l:option = get(a:000, 0, {})

  let l:params = {
  \   'on_stdout': function(self.on_stdout, [], self),
  \   'on_stderr': function(self.on_stderr, [], self),
  \   'on_exit': function(self.on_exit, [], self),
  \ }

  if has_key(l:option, 'cwd') && isdirectory(l:option.cwd)
    let l:params.cwd = l:option.cwd
  endif

  let self.job = jobstart(self.command, l:params)
  let self.running = v:true
endfunction

"
" stop
"
function! s:Nvim.stop() abort
  call jobstop(self.job)
  let self.job = v:null
endfunction

"
" send
"
function! s:Nvim.send(data) abort
  call jobsend(self.job, a:data)
endfunction

"
" is_running
"
function! s:Nvim.is_running() abort
  return self.running
endfunction

"
" on_stdout
"
function! s:Nvim.on_stdout(id, data, event) abort
  call self.emitter.emit('stdout', join(a:data, "\n"))
endfunction

"
" on_stderr
"
function! s:Nvim.on_stderr(id, data, event) abort
  call self.emitter.emit('stderr', join(a:data, "\n"))
endfunction

"
" on_exit
"
function! s:Nvim.on_exit(id, data, event) abort
  let self.running = v:false
  call self.emitter.emit('exit', a:data)
endfunction

"
" Vim
"
let s:Vim = {}

"
" new
"
function! s:Vim.new(args) abort
  return extend(deepcopy(s:Vim), {
  \   'running': v:false,
  \   'command': a:args.command,
  \   'emitter': s:Emitter.new(),
  \   'job': v:null,
  \ })
endfunction

"
" start
"
function! s:Vim.start(...) abort
  let l:option = get(a:000, 0, {})

  let l:params = {
  \   'in_io': 'pipe',
  \   'in_mode': 'raw',
  \   'out_io': 'pipe',
  \   'out_mode': 'raw',
  \   'err_io': 'pipe',
  \   'err_mode': 'raw',
  \   'out_cb': function(self.on_stdout, [], self),
  \   'err_cb': function(self.on_stderr, [], self),
  \   'exit_cb': function(self.on_exit, [], self)
  \ }

  if has_key(l:option, 'cwd') && isdirectory(l:option.cwd)
    let l:params.cwd = l:option.cwd
  endif

  let self.job = job_start(self.command, l:params)
  let self.running = v:true
endfunction

"
" stop
"
function! s:Vim.stop() abort
  if !empty(self.job)
    call ch_close(self.job)
  endif
  let self.job = v:null
endfunction

"
" send
"
function! s:Vim.send(data) abort
  call ch_sendraw(self.job, a:data)
endfunction

"
" is_running
"
function! s:Vim.is_running() abort
  return self.running
endfunction

"
" on_stdout
"
function! s:Vim.on_stdout(job, data) abort
  call self.emitter.emit('stdout', a:data)
endfunction

"
" on_stderr
"
function! s:Vim.on_stderr(job, data) abort
  call self.emitter.emit('stderr', a:data)
endfunction

"
" on_exit
"
function! s:Vim.on_exit(job, data) abort
  let self.running = v:false
  call self.emitter.emit('exit', a:data)
endfunction
