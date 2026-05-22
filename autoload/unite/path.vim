vim9script

var is_windows = has('win16') || has('win32') || has('win64') || has('win95')

export def SubstitutePathSeparator(path: string): string
  return is_windows ? substitute(path, '\\', '/', 'g') : path
enddef

export def ExpandPath(path: string): string
  return SubstitutePathSeparator(expand(path))
enddef

export def NormalizePath(path: string): string
  var normalized = SubstitutePathSeparator(fnamemodify(path, ':p'))
  if normalized !~ '\a\+:'
    normalized = SubstitutePathSeparator(simplify(resolve(normalized)))
  endif
  return substitute(normalized, '/$', '', '')
enddef
