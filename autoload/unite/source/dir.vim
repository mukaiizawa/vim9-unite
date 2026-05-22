vim9script

export def GatherCandidates(args: list<any>, ctx: dict<any>): list<dict<any>>
  var raw_items = call('unite#file#GatherDirectoryCandidates', [])
  var result: list<dict<any>> = []
  for item in raw_items
    if type(item) == v:t_dict
      add(result, copy(item))
      continue
    endif

    var path = item
    add(result, {
      word: path,
      action__path: path,
    })
  endfor
  return result
enddef
