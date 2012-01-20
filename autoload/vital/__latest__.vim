let s:self_version = expand('<sfile>:t:r')

let s:loaded = {}

function! s:import(name, ...)
  let module = s:_import(a:name, s:_scripts(), 0)
  if a:0 && type(a:1) == type({})
    call extend(a:1, module, 'keep')
  endif
  return module
endfunction

function! s:load(...) dict
  let scripts = s:_scripts()
  let debug = has_key(self, 'debug') && self.debug
  for arg in a:000
    let [name, as] = type(arg) == type([]) ? arg[: 1] : [arg, arg]
    let target = split(as, '\W\+')
    let dict = self
    while 2 <= len(target)
      let ns = remove(target, 0)
      if !has_key(dict, ns)
        let dict[ns] = {}
      endif
      if type(dict[ns]) == type({})
        let dict = dict[ns]
      else
        let target = []
      endif
    endwhile

    if !empty(target) && !has_key(dict, target[0])
      let dict[target[0]] = s:_import(name, scripts, debug)
    endif
    unlet arg
  endfor
  return self
endfunction

function! s:_import(name, scripts, debug)
  if type(a:name) == type(0)
    return s:_build_module(a:name, a:debug)
  endif
  if a:name =~# '^[^A-Z]' || a:name =~# '\W[^A-Z]'
    throw 'vital: module name must start with capital letter: ' . a:name
  endif
  let target = a:name ==# '' ? '' : '/' . substitute(a:name, '\W\+', '/', 'g')
  let target = substitute(target, '\l\zs\ze\u', '_', 'g') " OrderedSet -> Ordered_Set
  let target = substitute(target, '[/_]\zs\u', '\l\0', 'g') " Ordered_Set -> ordered_set
  let tailpath = printf('autoload/vital/%s%s.vim', s:self_version, target)
  let paths = split(globpath(&runtimepath, tailpath, 1), "\n")
  let path = s:_unify_path(get(paths, 0, ''))
  let sid = get(a:scripts, path, 0)
  if !sid
    try
      source `=path`
    catch /^Vim\%((\a\+)\)\?:E484/
      throw 'vital: module not found: ' . a:name
    endtry
    let sid = len(a:scripts) + 1  " We expect that the file newly read is +1.
    let a:scripts[path] = sid
  endif
  return s:_build_module(sid, a:debug)
endfunction

function! s:_scripts()
  let scripts = {}
  for line in split(s:_redir('scriptnames'), "\n")
    let list = matchlist(line, '^\s*\(\d\+\):\s\+\(.\+\)\s*$')
    if !empty(list)
      let scripts[s:_unify_path(list[2])] = list[1] - 0
    endif
  endfor
  return scripts
endfunction

function! s:_unify_path(path)
  return resolve(fnamemodify(a:path, ':p:gs?[\\/]\+?/?'))
endfunction

function! s:_build_module(sid, debug)
  if has_key(s:loaded, a:sid)
    return copy(s:loaded[a:sid])
  endif
  let prefix = '<SNR>' . a:sid . '_'
  let funcs = s:_redir('function')
  let filter_pat = '^\s*function ' . prefix
  let map_pat = prefix . '\zs\w\+'
  let functions = map(filter(split(funcs, "\n"), 'v:val =~# filter_pat'),
  \          'matchstr(v:val, map_pat)')

  let module = {}
  for func in functions
    let module[func] = function(prefix . func)
  endfor
  if has_key(module, '_vital_loaded')
    let V = vital#{s:self_version}#new()
    if has_key(module, '_vital_depends')
      call call(V.load, module._vital_depends(), V)
    endif
    try
      call module._vital_loaded(V)
    catch
      " FIXME: Show an error message for debug.
    endtry
  endif
  if !a:debug
    call filter(module, 'v:key =~# "^\\a"')
  endif
  let s:loaded[a:sid] = module
  return copy(module)
endfunction

function! s:_redir(cmd)
  redir => res
    silent! execute a:cmd
  redir END
  return res
endfunction

function! vital#{s:self_version}#new()
  let V = s:import('')
  call V.import('Prelude', V)
  return V
endfunction
