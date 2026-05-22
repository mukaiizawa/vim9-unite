vim9script

export def SetDefault(name: string, value: any)
  if !exists(name) || type(eval(name)) != type(value)
    execute printf('%s = %s', name, string(value))
  endif
enddef
