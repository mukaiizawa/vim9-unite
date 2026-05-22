vim9script

export def GatherCandidates(args: list<any>, ctx: dict<any>): list<dict<any>>
  var result: list<dict<any>> = []
  for candidate in call('unite#repo#Candidates', [])
    add(result, copy(candidate))
  endfor
  return result
enddef
