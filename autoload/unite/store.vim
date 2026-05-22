vim9script

export def IsSudo(): bool
  return $SUDO_USER != '' && $USER !=# $SUDO_USER
    && $HOME !=# expand('~' .. $USER)
    && $HOME ==# expand('~' .. $SUDO_USER)
enddef

export def WriteList(path: string, lines: list<string>)
  var absolute = fnamemodify(path, ':p')
  var parent = fnamemodify(absolute, ':h')
  if !isdirectory(parent)
    mkdir(parent, 'p')
  endif
  writefile(lines, absolute)
enddef
