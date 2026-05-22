vim9script

var yank_histories: dict<list<any>> = {}
var yank_histories_old: dict<list<any>> = {}
var yank_histories_file_mtime = 0
var prev_yankpost_event: dict<any> = {}
var is_windows = has('win16') || has('win32') || has('win64') || has('win95')

def AddRegister(name: string, reg: list<any>)
  if !has_key(yank_histories, name)
    yank_histories[name] = []
  endif
  if get(yank_histories[name], 0, []) ==# reg
    return
  endif

  var regcontents = reg[0]
  var len_history = type(regcontents) == v:t_list ? len(regcontents) : len(string(regcontents))
  if len_history < 2 || len_history > g:unite_yank_length
    return
  endif

  var text = type(regcontents) == v:t_list ? join(regcontents, "\n") : string(regcontents)
  if text =~ '[\x00-\x08\x10-\x1a\x1c-\x1f]\{3,}'
    return
  endif

  try
    json_encode(reg)
  catch
    return
  endtry

  insert(yank_histories[name], reg, 0)
  Uniq(name)
enddef

def Uniq(name: string)
  var history = get(yank_histories, name, [])
  var result: list<any> = []
  var seen: dict<bool> = {}
  for reg in history
    var key = json_encode(reg)
    if has_key(seen, key)
      continue
    endif
    seen[key] = true
    add(result, reg)
    if g:unite_yank_limit <= len(result)
      break
    endif
  endfor
  yank_histories[name] = result
enddef

def DefaultRegisterFromClipboard(): string
  if &clipboard ==# 'unnamed'
    return '*'
  elseif &clipboard ==# 'unnamedplus'
    return '+'
  endif
  return '"'
enddef

var base = is_windows
  ? substitute(expand($XDG_CACHE_HOME != '' ? $XDG_CACHE_HOME .. '/unite' : '~/.cache/unite'), '\\', '/', 'g')
  : expand($XDG_CACHE_HOME != '' ? $XDG_CACHE_HOME .. '/unite' : '~/.cache/unite')
unite#config#SetDefault('g:unite_yank_file', base .. '/history')
unite#config#SetDefault('g:unite_yank_limit', 100)
unite#config#SetDefault('g:unite_yank_length', 10000)
unite#config#SetDefault('g:unite_yank_save_registers', [DefaultRegisterFromClipboard()])
unite#config#SetDefault('g:unite_yank_disable_write', 0)

export def Update()
  Append()
enddef

export def Append()
  Load()
  for regname in g:unite_yank_save_registers
    AddRegister(regname, [getreg(regname), getregtype(regname)])
  endfor
  Save()
enddef

export def YankPost()
  if v:event ==# prev_yankpost_event
    return
  endif
  for regname in g:unite_yank_save_registers
    AddRegister(regname, [getreg(regname), getregtype(regname)])
  endfor
  prev_yankpost_event = copy(v:event)
enddef

export def GetHistories(): dict<list<any>>
  return yank_histories
enddef

export def Save()
  if g:unite_yank_file ==# ''
    return
  endif
  if unite#store#IsSudo() || g:unite_yank_disable_write
    return
  endif
  if yank_histories ==# yank_histories_old
    return
  endif

  unite#store#WriteList(g:unite_yank_file, [json_encode(yank_histories)])
  yank_histories_file_mtime = getftime(g:unite_yank_file)
  yank_histories_old = copy(yank_histories)
enddef

export def Load()
  if !filereadable(g:unite_yank_file) || yank_histories_file_mtime == getftime(g:unite_yank_file)
    return
  endif

  var file = readfile(g:unite_yank_file)
  if len(file) != 1
    return
  endif

  var loaded: dict<any> = {}
  try
    loaded = json_decode(file[0])
  catch
    loaded = {}
  endtry
  if type(loaded) != v:t_dict
    loaded = {}
  endif

  for regname in g:unite_yank_save_registers
    if !has_key(yank_histories, regname)
      yank_histories[regname] = []
    endif
    yank_histories[regname] = get(loaded, regname, []) + yank_histories[regname]
    Uniq(regname)
  endfor
  yank_histories_file_mtime = getftime(g:unite_yank_file)
enddef
