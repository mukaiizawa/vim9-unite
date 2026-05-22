vim9script

var is_windows = has('win16') || has('win32') || has('win64') || has('win95')

def IsFileCandidate(path: string): bool
  var ignore = !empty(g:unite_file_mru_ignore_pattern) && path =~ g:unite_file_mru_ignore_pattern
  return !ignore && (getftype(path) ==# 'file' || getftype(path) ==# 'link' || path =~ '^\h\w\+:')
enddef

def IsDirectoryCandidate(path: string): bool
  var ignore = !empty(g:unite_directory_mru_ignore_pattern) && path =~ g:unite_directory_mru_ignore_pattern
  return !ignore && (isdirectory(path) || path =~ '^\h\w\+:')
enddef

def Uniq(paths: list<string>): list<string>
  var result: list<string> = []
  var seen: dict<bool> = {}
  for path in paths
    if empty(path)
      continue
    endif
    var key = tolower(path)
    if has_key(seen, key)
      continue
    endif
    seen[key] = true
    add(result, path)
  endfor
  return result
enddef

class FileStore
  var type = ''
  var mru_file = ''
  var limit = 1000
  var update_interval = 0
  var do_validate = true
  var candidates: list<string> = []
  var mtime = 0
  var is_loaded = false

  def new(type: string, mru_file: string, limit: number)
    this.type = type
    this.mru_file = unite#path#ExpandPath(mru_file)
    this.limit = limit
    this.update_interval = g:unite_file_update_interval
    this.do_validate = g:unite_file_do_validate
  enddef

  def HasExternalUpdate(): bool
    return this.mtime < getftime(this.mru_file)
  enddef

  def Validate()
    if !this.do_validate
      return
    endif
    if this.type ==# 'file'
      filter(this.candidates, (_, path) => IsFileCandidate(path))
      return
    endif
    filter(this.candidates, (_, path) => IsDirectoryCandidate(path))
  enddef

  def Load(force: bool = false)
    if !force && this.is_loaded && !this.HasExternalUpdate()
      return
    endif
    if !filereadable(this.mru_file)
      return
    endif
    if force
      this.candidates = []
      this.is_loaded = false
    endif

    var file = readfile(this.mru_file)
    if empty(file)
      return
    endif

    extend(this.candidates, file)
    this.candidates = Uniq(this.candidates)
    this.mtime = getftime(this.mru_file)
    this.is_loaded = true
  enddef

  def Reload()
    this.Load(true)
    this.Validate()
  enddef

  def Save(opts: dict<any> = {})
    if unite#store#IsSudo()
      return
    endif

    if this.HasExternalUpdate() && filereadable(this.mru_file)
      var latest = readfile(this.mru_file)
      extend(this.candidates, latest)
    endif

    this.candidates = Uniq(this.candidates)
    if len(this.candidates) > this.limit
      this.candidates = this.candidates[: this.limit - 1]
    endif
    if get(opts, 'event', '') ==# 'VimLeavePre'
      this.Validate()
    endif

    unite#store#WriteList(this.mru_file, this.candidates)
    this.mtime = getftime(this.mru_file)
    this.is_loaded = true
  enddef

  def Append(path: string)
    this.Load()
    var index = index(this.candidates, path)
    if index == 0
      return
    endif
    if index > 0
      remove(this.candidates, index)
    endif
    insert(this.candidates, path)

    if len(this.candidates) > this.limit
      this.candidates = this.candidates[: this.limit - 1]
    endif
    if localtime() > getftime(this.mru_file) + this.update_interval
      this.Save()
    endif
  enddef

  def GatherCandidates(): list<dict<any>>
    this.Load()
    return mapnew(copy(this.candidates), (_, path) => ({
      word: path,
      abbr: Abbr(path, getftime(path)),
      action__path: path,
    }))
  enddef
endclass

var base = is_windows
  ? substitute(expand($XDG_CACHE_HOME != '' ? $XDG_CACHE_HOME .. '/unite' : '~/.cache/unite'), '\\', '/', 'g')
  : expand($XDG_CACHE_HOME != '' ? $XDG_CACHE_HOME .. '/unite' : '~/.cache/unite')

unite#config#SetDefault('g:unite_file_do_validate', 1)
unite#config#SetDefault('g:unite_file_update_interval', 0)
unite#config#SetDefault('g:unite_file_time_format', '')
unite#config#SetDefault('g:unite_file_mru_path', unite#path#SubstitutePathSeparator(base .. '/mru-file'))
unite#config#SetDefault('g:unite_file_mru_limit', 1000)
unite#config#SetDefault('g:unite_file_mru_ignore_pattern', '\~$\|\.\%(o\|exe\|dll\|bak\|zwc\|pyc\|sw[po]\)$' .. '\|\%(^\|/\)\.\%(hg\|git\|bzr\|svn\)\%($\|/\)' .. '\|^\%(\\\\\|/mnt/\|/media/\|/temp/\|/tmp/\|\%(/private\)\=/var/folders/\)' .. '\|\%(^\%(fugitive\)://\)' .. '\|\%(^\%(term\)://\)')
unite#config#SetDefault('g:unite_directory_mru_path', unite#path#SubstitutePathSeparator(base .. '/mru-directory'))
unite#config#SetDefault('g:unite_directory_mru_limit', 1000)
unite#config#SetDefault('g:unite_directory_mru_ignore_pattern', '\%(^\|/\)\.\%(hg\|git\|bzr\|svn\)\%($\|/\)' .. '\|^\%(\\\\\|/mnt/\|/media/\|/temp/\|/tmp/\|\%(/private\)\=/var/folders/\)')

var file_mru = FileStore.new('file', g:unite_file_mru_path, g:unite_file_mru_limit)
var directory_mru = FileStore.new('directory', g:unite_directory_mru_path, g:unite_directory_mru_limit)

export def AppendCurrent()
  if &l:buftype =~# 'help\|nofile' || &l:previewwindow
    return
  endif
  Append(expand('%:p'))
enddef

export def GatherFileCandidates(): list<dict<any>>
  return file_mru.GatherCandidates()
enddef

export def GatherDirectoryCandidates(): list<dict<any>>
  return directory_mru.GatherCandidates()
enddef

export def Append(filename: string)
  var path = unite#path#NormalizePath(filename)
  if IsFileCandidate(path)
    file_mru.Append(path)
  endif

  var bufnr_value = bufnr(filename)
  var filetype = bufnr_value > 0 ? getbufvar(bufnr_value, '&filetype') : ''
  if filetype ==# 'vimfiler' && type(getbufvar(bufnr_value, 'vimfiler')) == v:t_dict
    path = getbufvar(bufnr_value, 'vimfiler').current_dir
  elseif filetype ==# 'vimshell' && type(getbufvar(bufnr_value, 'vimshell')) == v:t_dict
    path = getbufvar(bufnr_value, 'vimshell').current_dir
  else
    path = fnamemodify(path, ':p:h')
  endif

  path = unite#path#NormalizePath(path)
  if IsDirectoryCandidate(path)
    directory_mru.Append(path)
  endif
enddef

export def Reload()
  file_mru.Reload()
  directory_mru.Reload()
enddef

export def Save(opts: dict<any> = {})
  file_mru.Save(opts)
  directory_mru.Save(opts)
enddef

export def Abbr(path: string, time: number): string
  var abbr = g:unite_file_time_format ==# '' ? '' : strftime('(' .. g:unite_file_time_format .. ') ', time)
  return abbr .. path
enddef
