vim9script

var is_windows = has('win16') || has('win32') || has('win64') || has('win95')
var repositories: list<string> = []
var is_loaded = false

def PathToDirectory(path: string): string
  return unite#path#SubstitutePathSeparator(isdirectory(path) ? path : fnamemodify(path, ':p:h'))
enddef

def PathToRepositoryGit(path: string): string
  var parent = path
  while true
    var git_path = parent .. '/.git'
    if isdirectory(git_path) || filereadable(git_path)
      return parent
    endif
    var next = fnamemodify(parent, ':h')
    if next ==# parent
      return ''
    endif
    parent = next
  endwhile
  return ''
enddef

def PathToRepositorySvn(path: string): string
  var parent = path
  while true
    if isdirectory(parent .. '/.svn')
      return parent
    endif
    var next = fnamemodify(parent, ':h')
    if next ==# parent
      return ''
    endif
    parent = next
  endwhile
  return ''
enddef

def PathToRepository(path: string): string
  var directory = PathToDirectory(path)
  for vcs in ['.git', '.svn']
    var root = vcs ==# '.git' ? PathToRepositoryGit(directory) : PathToRepositorySvn(directory)
    if !empty(root)
      return unite#path#NormalizePath(root)
    endif
  endfor
  return ''
enddef

def Uniq(list: list<string>): list<string>
  var result: list<string> = []
  var seen: dict<bool> = {}
  for item in list
    if empty(item)
      continue
    endif
    var key = tolower(item)
    if has_key(seen, key)
      continue
    endif
    seen[key] = true
    add(result, item)
  endfor
  return result
enddef

def Load()
  if is_loaded
    return
  endif
  if filereadable(g:unite_repo_path)
    repositories = Uniq(readfile(g:unite_repo_path))
  else
    repositories = []
  endif
  is_loaded = true
enddef

def AppendRepository(path: string)
  Load()
  var i = 0
  while i < len(repositories)
    if tolower(repositories[i]) ==# tolower(path)
      remove(repositories, i)
      break
    endif
    i += 1
  endwhile
  insert(repositories, path, 0)
enddef

var base = is_windows
  ? substitute(expand($XDG_CACHE_HOME != '' ? $XDG_CACHE_HOME .. '/unite' : '~/.cache/unite'), '\\', '/', 'g')
  : expand($XDG_CACHE_HOME != '' ? $XDG_CACHE_HOME .. '/unite' : '~/.cache/unite')
unite#config#SetDefault('g:unite_repo_path', base .. '/repositories')

export def Append(filename: string)
  var path = unite#path#NormalizePath(filename)
  if empty(path) || getftype(path) !~# 'file\|dir\|link'
    return
  endif
  var root = PathToRepository(path)
  if empty(root)
    return
  endif
  AppendRepository(root)
enddef

export def AppendCurrent()
  if &l:buftype =~# 'help\|nofile' || &l:previewwindow
    return
  endif
  Append(unite#path#ExpandPath('%:p'))
enddef

export def Repository(path: string): string
  var normalized = unite#path#NormalizePath(path)
  return empty(normalized) ? '' : PathToRepository(normalized)
enddef

export def CurrentRepository(): string
  if &l:buftype =~# 'help\|nofile' || &l:previewwindow
    return ''
  endif
  var path = unite#path#ExpandPath('%:p')
  if empty(path) || getftype(path) !~# 'file\|link'
    return ''
  endif
  return Repository(path)
enddef

export def Candidates(): list<dict<any>>
  Load()
  return mapnew(copy(repositories), (_, path) => ({
    word: path,
    action__path: path,
  }))
enddef

export def Reload()
  is_loaded = false
  repositories = []
  Load()
enddef

export def Save()
  Load()
  unite#store#WriteList(g:unite_repo_path, repositories)
enddef
