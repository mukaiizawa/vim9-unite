vim9script

export def GatherCandidates(args: list<any>, ctx: dict<any>): list<dict<any>>
  var raw_items = call('unite#file#GatherFileCandidates', [])
  var result: list<dict<any>> = []
  for item in raw_items
    if type(item) == v:t_dict
      add(result, copy(item))
      continue
    endif

    var path = item
    add(result, {
      word: path,
      abbr: exists('*unite#file#Abbr') == 1 ? call('unite#file#Abbr', [path, getftime(path)]) : path,
      action__path: path,
    })
  endfor
  return result
enddef
