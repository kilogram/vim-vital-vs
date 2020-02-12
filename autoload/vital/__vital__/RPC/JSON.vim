"
" _vital_loaded
"
function! s:_vital_loaded(V) abort
  let s:Job = a:V.import('System.Job')
  let s:Promise = a:V.import('Async.Promise')
  let s:Emitter = a:V.import('Event.Emitter')
endfunction

"
" _vital_depends
"
function! s:_vital_depends() abort
  return ['Event.Emitter', 'System.Job', 'Async.Promise']
endfunction

"
" new
"
function! s:new(args) abort
  return s:Connection.new(a:args)
endfunction

"
" s:Connection
"
let s:Connection = {}

"
" new
"
function! s:Connection.new(args) abort
  return extend(deepcopy(s:Connection), {
  \   'job': s:Job.new({ 'command': a:args.command }),
  \   'emitter': s:Emitter.new(),
  \   'buffer':  '',
  \   'request_id': 0,
  \   'request_map': {},
  \ })
endfunction

"
" start
"
function! s:Connection.start() abort
  if !self.job.is_running()
    call self.job.emitter.on('stdout', self.on_stdout)
    call self.job.emitter.on('stderr', self.on_stderr)
    call self.job.emitter.on('ext', self.on_exit)
    call self.job.start()
  endif
endfunction

"
" stop
"
function! s:Connection.stop() abort
  if self.job.is_running()
    call self.job.emitter.off('stdout', self.on_stdout)
    call self.job.emitter.off('stderr', self.on_stderr)
    call self.job.emitter.off('ext', self.on_exit)
    call self.job.stop()
  endif
endfunction

"
" is_running
"
function! s:Connection.is_running() abort
  return self.job.is_running()
endfunction

"
" request
"
function! s:Connection.request(method, ...) abort
  let l:ctx = {}
  function! l:ctx.callback(message, resolve, reject) abort
    let self.request_id += 1
    let self.request_map[self.request_id] = {}
    let self.request_map[self.request_id].resolve = a:resolve
    let self.request_map[self.request_id].reject = a:reject
    call self.job.send(self.to_message(extend({ 'id': self.request_id }, a:message)))
  endfunction

  let l:message = extend({ 'method': a:method }, len(a:000) > 0 ? { 'params': a:000[0] } : {})
  return s:Promise.new(function(l:ctx.callback, [l:message], self))
endfunction

"
" response
"
function! s:Connection.response(id, ...) abort
 call self.job.send(self.to_message(extend({ 'id': a:id }, len(a:000) > 0 ? a:000[0] : {})))
endfunction

"
" notify
"
function! s:Connection.notify(method, ...) abort
  call self.job.send(extend({ 'method': a:method }, len(a:000) > 0 ? { 'params': a:000[0] } : {}))
endfunction

"
" to_message
"
function! s:Connection.to_message(message) abort
  let l:message = json_encode(extend({ 'jsonrpc': '2.0' }, a:message))
  return 'Content-Length: ' . strlen(l:message) . "\r\n\r\n" . l:message
endfunction

"
" on_message
"
function! s:Connection.on_message(message) abort
  if has_key(a:message, 'id')
    " Response from server.
    if has_key(self.request_map, a:message.id)
      if has_key(a:message, 'error')
        call self.request_map[a:message.id].reject(a:message.error)
      else
        call self.request_map[a:message.id].resolve(get(a:message, 'result', v:null))
      endif
      call remove(self.request_map, a:message.id)

    " Request from server.
    else
      call self.emitter.emit('request', a:message)
    endif
    return
  endif

  " Notification from server.
  if has_key(a:message, 'method')
    call self.emitter.emit('notify', a:message)
  endif
endfunction

"
" on_stdout
"
function! s:Connection.on_stdout(data) abort
  let self.buffer .= a:data

  " header check.
  let l:header_length = stridx(self.buffer, "\r\n\r\n") + 4
  if l:header_length < 4
    return
  endif

  " content length check.
  let l:content_length = get(matchlist(self.buffer[0 : l:header_length - 1], 'Content-Length: \(\d\+\)'), 1, v:null)
  if l:content_length is v:null
    return
  endif
  let l:end_of_content = l:header_length + l:content_length

  " content check.
  let l:buffer_len = strlen(self.buffer)
  if l:buffer_len < l:end_of_content
    return
  endif

  " try content.
  try
    let l:message = json_decode(trim(self.buffer[l:header_length : l:end_of_content - 1]))
    let self.buffer = self.buffer[l:end_of_content : ]

    call self.on_message(l:message)

    if l:buffer_len > l:end_of_content
      call self.on_stdout('')
    endif
  catch /.*/
  endtry
endfunction

"
" on_stderr
"
function! s:Connection.on_stderr(data) abort
  call self.emitter.emit('stderr', a:data)
endfunction

"
" on_exit
"
function! s:Connection.on_exit(code) abort
  call self.emitter.emit('exit', a:code)
endfunction

