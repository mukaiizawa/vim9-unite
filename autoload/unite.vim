vim9script

var sources: dict<dict<any>> = {}
var states: dict<dict<any>> = {}

def InitBuiltins()
  if !empty(sources)
    return
  endif

  sources['line'] = {
    gather: function('unite#source#line#GatherCandidates'),
  }
  sources['menu'] = {
    gather: function('unite#source#menu#GatherCandidates'),
    default_action: 'execute',
  }
  sources['file'] = {
    gather: function('unite#source#file#GatherCandidates'),
  }
  sources['dir'] = {
    gather: function('unite#source#directory#GatherCandidates'),
    default_action: 'open',
  }
  sources['yank'] = {
    gather: function('unite#source#yank#GatherCandidates'),
    default_action: 'setreg',
  }
  sources['quickfix'] = {
    gather: function('unite#source#quickfix#GatherCandidates'),
  }
  sources['repo'] = {
    gather: function('unite#source#repo#GatherCandidates'),
    default_action: 'open',
  }
enddef

def ParseArgv(qargs: string): list<string>
  return split(qargs)
enddef

def ParseOptions(argv: list<string>): dict<any>
  var opts = {
    source: '',
    source_args: [],
    split: true,
    focus: true,
  }

  if empty(argv)
    throw 'Unite: source is required'
  endif

  opts.source = remove(argv, 0)

  for arg in argv
    add(opts.source_args, arg)
  endfor

  return opts
enddef

def SourceByName(name: string): dict<any>
  InitBuiltins()
  if !has_key(sources, name)
    throw printf('Unite: source not found: %s', name)
  endif
  return sources[name]
enddef

def CandidateLabel(candidate: dict<any>, state: dict<any>): string
  return get(candidate, 'abbr', get(candidate, 'word', ''))
enddef

def CandidateFilterText(candidate: dict<any>): string
  return get(candidate, 'word', get(candidate, 'abbr', ''))
enddef

def ClearMatchHighlights(state: dict<any>)
  if !has_key(state, 'match_ids') || empty(get(state, 'match_ids', []))
    state.match_ids = []
    return
  endif

  var winid = get(state, 'picker_winid', -1)
  if winid <= 0 || win_id2win(winid) <= 0
    state.match_ids = []
    return
  endif

  for match_id in state.match_ids
    try
      win_execute(winid, printf('call matchdelete(%d)', match_id))
    catch
    endtry
  endfor
  state.match_ids = []
enddef

def UpdateMatchHighlights(state: dict<any>)
  ClearMatchHighlights(state)

  var tokens = split(tolower(state.query))
  if empty(tokens)
    return
  endif

  var winid = get(state, 'picker_winid', -1)
  if winid <= 0 || win_id2win(winid) <= 0
    return
  endif

  highlight default link UniteMatchedText Search
  for token in tokens
    if empty(token)
      continue
    endif

    var literal = escape(token, '\.^$~[]*')
    var pattern = '\c\%>1l' .. literal
    var match_id = str2nr(win_execute(winid, printf('echo matchadd(%s, %s)', string('UniteMatchedText'), string(pattern))))
    if match_id > 0
      add(state.match_ids, match_id)
    endif
  endfor
enddef

def FilterCandidates(state: dict<any>): list<dict<any>>
  var query = tolower(state.query)
  if empty(query)
    return copy(state.all_candidates)
  endif
  var tokens = split(query)
  if empty(tokens)
    return copy(state.all_candidates)
  endif

  var filtered: list<dict<any>> = []
  for candidate in state.all_candidates
    var haystack = tolower(CandidateFilterText(candidate))
    var matched = true
    for token in tokens
      if stridx(haystack, token) < 0
        matched = false
        break
      endif
    endfor
    if matched
      add(filtered, candidate)
    endif
  endfor

  return filtered
enddef

def Render(bufnr_value: number, keep_prompt_cursor: bool = false)
  if !has_key(states, string(bufnr_value))
    return
  endif

  var state = states[string(bufnr_value)]
  state.filtered_candidates = FilterCandidates(state)
  if empty(state.filtered_candidates)
    state.selected = 0
  elseif state.selected >= len(state.filtered_candidates)
    state.selected = len(state.filtered_candidates) - 1
  elseif state.selected < -1
    state.selected = -1
  endif

  var lines = [state.prompt .. state.query]
  if !empty(state.filtered_candidates)
    for candidate in state.filtered_candidates
      add(lines, CandidateLabel(candidate, state))
    endfor
  endif

  setbufline(bufnr_value, 1, lines)
  var total_lines = len(getbufline(bufnr_value, 1, '$'))
  if total_lines > len(lines)
    deletebufline(bufnr_value, len(lines) + 1, '$')
  endif

  states[string(bufnr_value)] = state
  UpdateMatchHighlights(state)
  states[string(bufnr_value)] = state
  if !keep_prompt_cursor && mode() !~# '^i'
    CursorToSelection(bufnr_value)
  endif
enddef

def CursorToSelection(bufnr_value: number)
  if !has_key(states, string(bufnr_value))
    return
  endif

  var state = states[string(bufnr_value)]
  var line_nr = empty(state.filtered_candidates) || state.selected < 0 ? 1 : state.selected + 2
  cursor(line_nr, 1)
enddef

def SetupSyntax(state: dict<any>)
  syntax clear

  if state.source_name ==# 'line'
    syntax match UniteLineNr /^\s*\d\+:/ containedin=ALL
    highlight default link UniteLineNr LineNr
  endif
enddef

def SyncSelectionFromCursor(bufnr_value: number)
  if !has_key(states, string(bufnr_value))
    return
  endif

  var state = states[string(bufnr_value)]
  if empty(state.filtered_candidates)
    state.selected = 0
    states[string(bufnr_value)] = state
    return
  endif

  var current_line = line('.')
  if current_line <= 1
    state.selected = -1
  else
    state.selected = current_line - 2
    state.selected = max([0, min([state.selected, len(state.filtered_candidates) - 1])])
  endif
  states[string(bufnr_value)] = state
enddef

def OpenWindow(opts: dict<any>)
  execute 'topleft new'
  execute 'resize 10'
enddef

def PickerBufferName(source_name: string): string
  return printf('[unite] - %s', source_name)
enddef

def CloseExistingPickers(skip_winid: number = -1)
  var to_close: list<number> = []
  for nr in range(1, winnr('$'))
    var bufnr_value = winbufnr(nr)
    var winid = win_getid(nr)
    if winid != skip_winid
          && bufnr_value > 0
          && getbufvar(bufnr_value, '&filetype') ==# 'unite'
      add(to_close, win_getid(nr))
    endif
  endfor

  reverse(to_close)
  for winid in to_close
    if win_id2win(winid) > 0
      win_gotoid(winid)
      close
    endif
  endfor
enddef

def SetupBuffer(state: dict<any>)
  execute 'file ' .. fnameescape(PickerBufferName(state.source_name))
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal modifiable
  setlocal nolist
  setlocal nowrap
  setlocal filetype=unite cursorline nospell nonumber norelativenumber
  setlocal statusline=%F%=%l/%L
  setlocal nomodified
  setlocal undolevels=-1
  SetupSyntax(state)

  nnoremap <silent><buffer> d <Nop>
  nnoremap <silent><buffer> D <Nop>
  nnoremap <silent><buffer> x <Cmd>call unite#DeleteForwardChar()<CR>
  nnoremap <silent><buffer> X <Nop>
  nnoremap <silent><buffer> s <Nop>
  nnoremap <silent><buffer> r <Nop>
  nnoremap <silent><buffer> R <Nop>
  nnoremap <silent><buffer> o <Nop>
  nnoremap <silent><buffer> O <Nop>
  nnoremap <silent><buffer> p <Nop>
  nnoremap <silent><buffer> P <Nop>
  nnoremap <silent><buffer> J <Nop>
  nnoremap <silent><buffer> q <Nop>
  nnoremap <silent><buffer> cc <Cmd>call unite#ClearPromptAndInsert()<CR>
  nnoremap <silent><buffer> C <Cmd>call unite#ClearPromptAndInsert()<CR>
  nnoremap <silent><buffer> S <Cmd>call unite#ClearPromptAndInsert()<CR>
  nnoremap <silent><buffer> a <Cmd>call unite#EnterInsertAtEnd()<CR>
  nnoremap <silent><buffer> i <Cmd>call unite#EnterInsertAtEnd()<CR>
  nnoremap <silent><buffer> I <Cmd>call unite#EnterInsertAtStart()<CR>
  nnoremap <silent><buffer> A <Cmd>call unite#EnterInsertAtEnd()<CR>
  nnoremap <silent><buffer> <C-h> <Cmd>call unite#DeleteBackwardChar()<CR>
  nnoremap <silent><buffer> <C-l> <Cmd>call unite#RedrawPicker()<CR>
  nnoremap <silent><buffer> <CR> <Cmd>call unite#ExecuteDefaultAction()<CR>

  inoremap <silent><buffer> <CR> <Esc><Cmd>call unite#ExecuteDefaultActionFromInsert()<CR>
  inoremap <silent><buffer> <Esc> <Esc>
  inoremap <silent><expr><buffer> <C-h> unite#InsertBackspace()
  inoremap <silent><expr><buffer> <BS> unite#InsertBackspace()

  augroup unite_buffer
    autocmd! * <buffer>
    autocmd CursorMoved <buffer> call unite#SyncCursorSelection()
    autocmd TextChanged,TextChangedI <buffer> call unite#SyncPrompt()
    autocmd BufWipeout <buffer> call unite#CleanupBuffer(expand('<abuf>'))
  augroup END
enddef

def StateForCurrentBuffer(): dict<any>
  var key = string(bufnr('%'))
  if !has_key(states, key)
    throw 'Unite: state not found for current buffer'
  endif
  return states[key]
enddef

export def StartCommand(qargs: string)
  try
    var argv = ParseArgv(qargs)
    var opts = ParseOptions(argv)
    var source = SourceByName(opts.source)
    var current_winid = win_getid()
    var current_bufnr = bufnr('%')
    var reusing_picker = &filetype ==# 'unite'
    var origin_winid = current_winid
    var origin_bufnr = current_bufnr
    if reusing_picker
      var previous = StateForCurrentBuffer()
      origin_winid = previous.context.origin_winid
      origin_bufnr = previous.context.origin_bufnr
    endif
    var ctx = {
      source_name: opts.source,
      origin_winid: origin_winid,
      origin_bufnr: origin_bufnr,
      options: opts,
    }
    var candidates = source.gather(opts.source_args, ctx)
    if type(candidates) != v:t_list
      throw printf('Unite: source %s did not return a list', opts.source)
    endif
    if empty(candidates)
      return
    endif

    CloseExistingPickers(reusing_picker ? current_winid : -1)
    if !reusing_picker
      OpenWindow(opts)
    endif
    var state = {
      prompt: '> ',
      query: '',
      source_name: opts.source,
      source: source,
      options: opts,
      context: ctx,
      all_candidates: candidates,
      filtered_candidates: [],
      selected: 0,
      picker_bufnr: bufnr('%'),
      picker_winid: win_getid(),
    }
    states[string(bufnr('%'))] = state
    SetupBuffer(state)
    Render(bufnr('%'))
    EnterInsertAtEnd()
  catch
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
enddef

export def RegisterSource(name: string, source: dict<any>)
  sources[name] = source
enddef

export def SyncPrompt()
  try
    var state = StateForCurrentBuffer()
    var was_prompt_line = line('.') == 1
    var current_col = col('.')
    var prompt_line = getline(1)
    if prompt_line =~# '^' .. escape(state.prompt, '\')
      state.query = prompt_line[len(state.prompt) : ]
    else
      state.query = prompt_line
    endif
    states[string(bufnr('%'))] = state
    Render(bufnr('%'), was_prompt_line)
    if mode() =~# '^i'
      cursor(1, len(state.prompt .. state.query) + 1)
    elseif was_prompt_line
      cursor(1, min([current_col, len(state.prompt .. state.query) + 1]))
    endif
  catch
  endtry
enddef

export def MoveSelection(delta: number)
  SyncSelectionFromCursor(bufnr('%'))
  var state = StateForCurrentBuffer()
  if empty(state.filtered_candidates)
    return
  endif
  state.selected += delta
  state.selected = max([-1, min([state.selected, len(state.filtered_candidates) - 1])])
  states[string(bufnr('%'))] = state
  CursorToSelection(bufnr('%'))
enddef

export def MoveToEdge(to_last: number)
  var state = StateForCurrentBuffer()
  if empty(state.filtered_candidates)
    return
  endif
  state.selected = to_last ? len(state.filtered_candidates) - 1 : -1
  states[string(bufnr('%'))] = state
  CursorToSelection(bufnr('%'))
enddef

export def SyncCursorSelection()
  SyncSelectionFromCursor(bufnr('%'))
enddef

export def EnterInsertAtStart()
  cursor(1, len('> ') + 1)
  startinsert
enddef

export def EnterInsertAtEnd()
  var state = StateForCurrentBuffer()
  cursor(1, len(state.prompt .. state.query) + 1)
  startinsert!
enddef

export def ClearPromptAndInsert()
  var state = StateForCurrentBuffer()
  state.query = ''
  states[string(bufnr('%'))] = state
  Render(bufnr('%'))
  EnterInsertAtEnd()
enddef

export def InsertBackspace(): string
  var state = StateForCurrentBuffer()
  var prompt_end_col = len(state.prompt) + 1
  if col('.') <= prompt_end_col
    return ''
  endif
  return "\<BS>"
enddef

export def DeleteBackwardChar()
  var state = StateForCurrentBuffer()
  if empty(state.query)
    EnterInsertAtEnd()
    return
  endif
  state.query = state.query[0 : len(state.query) - 2]
  states[string(bufnr('%'))] = state
  Render(bufnr('%'))
  EnterInsertAtEnd()
enddef

export def DeleteForwardChar()
  var state = StateForCurrentBuffer()
  var prompt_col = len(state.prompt) + 1
  if line('.') != 1
    return
  endif

  var cursor_col = max([col('.'), prompt_col])
  var query_idx = cursor_col - prompt_col
  if query_idx >= len(state.query)
    cursor(1, len(state.prompt .. state.query) + 1)
    return
  endif

  var before = query_idx == 0 ? '' : state.query[0 : query_idx - 1]
  var after = query_idx + 1 >= len(state.query) ? '' : state.query[query_idx + 1 : ]
  state.query = before .. after
  states[string(bufnr('%'))] = state
  Render(bufnr('%'), true)
  cursor(1, min([cursor_col, len(state.prompt .. state.query) + 1]))
enddef

export def RedrawPicker()
  redraw
  Render(bufnr('%'))
enddef

def InferDefaultAction(candidate: dict<any>): string
  if has_key(candidate, 'action__command')
    return 'execute'
  endif
  if has_key(candidate, 'action__regcontents')
    return 'setreg'
  endif
  if has_key(candidate, 'action__path') || has_key(candidate, 'action__bufnr') || has_key(candidate, 'action__line')
    return 'open'
  endif

  return 'setreg'
enddef

def ResolveDefaultAction(state: dict<any>, candidate: dict<any>): string
  if has_key(state.source, 'default_action') && !empty(state.source.default_action)
    return state.source.default_action
  endif
  return InferDefaultAction(candidate)
enddef

def ClosePickerWindow(state: dict<any>)
  var picker_winnr = win_id2win(state.picker_winid)
  if picker_winnr <= 0
    return
  endif

  var origin_exists = win_id2win(state.context.origin_winid) > 0
  if origin_exists
    win_gotoid(state.context.origin_winid)
  endif
  if win_id2win(state.picker_winid) > 0
    win_gotoid(state.picker_winid)
    close
  endif
  if origin_exists && win_id2win(state.context.origin_winid) > 0
    win_gotoid(state.context.origin_winid)
  endif
enddef

def PrepareTargetWindow(state: dict<any>)
  if win_id2win(state.context.origin_winid) > 0
    win_gotoid(state.context.origin_winid)
  endif
  ClosePickerWindow(state)
enddef

def ActionOpen(candidate: dict<any>, state: dict<any>)
  PrepareTargetWindow(state)
  if has_key(candidate, 'action__path')
    execute 'edit ' .. fnameescape(candidate.action__path)
  elseif has_key(candidate, 'action__bufnr')
    execute printf('buffer %d', candidate.action__bufnr)
  elseif has_key(candidate, 'action__line')
    execute printf('buffer %d', state.context.origin_bufnr)
  else
    throw 'Unite: open action requires action target'
  endif

  if has_key(candidate, 'action__line')
    cursor(candidate.action__line, get(candidate, 'action__col', 1))
  endif
enddef

def ActionSetReg(candidate: dict<any>)
  if has_key(candidate, 'action__regcontents')
    setreg('"', candidate.action__regcontents, get(candidate, 'action__regtype', 'v'))
    return
  endif
  setreg('"', get(candidate, 'word', ''))
enddef

def ActionExecute(candidate: dict<any>)
  if !has_key(candidate, 'action__command')
    throw 'Unite: execute action requires action__command'
  endif
  execute candidate.action__command
enddef

def ExecuteSelectedCandidate()
  var state = StateForCurrentBuffer()
  if empty(state.filtered_candidates) || state.selected < 0
    return
  endif

  var candidate = state.filtered_candidates[state.selected]
  var action = ResolveDefaultAction(state, candidate)
  if action ==# 'open'
    ActionOpen(candidate, state)
  elseif action ==# 'setreg'
    ActionSetReg(candidate)
    ClosePickerWindow(state)
  elseif action ==# 'execute'
    ClosePickerWindow(state)
    ActionExecute(candidate)
  else
    throw printf('Unite: action not supported: %s', action)
  endif
enddef

export def ExecuteDefaultAction()
  try
    SyncSelectionFromCursor(bufnr('%'))
    ExecuteSelectedCandidate()
  catch
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
enddef

export def ExecuteDefaultActionFromInsert()
  try
    var state = StateForCurrentBuffer()
    state.filtered_candidates = FilterCandidates(state)
    if empty(state.filtered_candidates)
      states[string(bufnr('%'))] = state
      return
    endif

    if state.selected < 0 || state.selected >= len(state.filtered_candidates)
      state.selected = 0
    endif
    states[string(bufnr('%'))] = state
    ExecuteSelectedCandidate()
  catch
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
enddef

export def ClosePicker()
  try
    var state = StateForCurrentBuffer()
    ClosePickerWindow(state)
  catch
    bwipeout!
  endtry
enddef

export def CleanupBuffer(bufnr_text: string)
  if has_key(states, bufnr_text)
    var state = states[bufnr_text]
    ClearMatchHighlights(state)
  endif
  remove(states, bufnr_text)
enddef
