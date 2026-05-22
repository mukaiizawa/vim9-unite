vim9script

export def GatherCandidates(args: list<any>, ctx: dict<any>): list<dict<any>>
  call('unite#yank#Load', [])
  var histories = call('unite#yank#GetHistories', [])
  var registers = exists('g:unite_yank_save_registers') ? g:unite_yank_save_registers : ['"']
  var result: list<dict<any>> = []
  for regname in registers
    for entry in get(histories, regname, [])
      if len(entry) < 2
        continue
      endif
      var text = entry[0]
      if type(text) == v:t_list
        text = join(text, "\n")
      endif
      var display = substitute(text, '\n', '\\n', 'g')
      display = substitute(display, '\x00', '', 'g')
      add(result, {
        word: display,
        abbr: display,
        action__regcontents: entry[0],
        action__regtype: entry[1],
      })
    endfor
  endfor
  return result
enddef
