# vim9-unite

`vim9-unite` is a small picker UI core written in Vim9 script.

It is inspired by [unite.vim](https://github.com/Shougo/unite.vim), but the scope is intentionally much smaller:

- This repository owns only picker UI and state management.
- It does not ship built-in sources.
- It does not ship built-in actions.
- Registration is expected to happen in your own Vim runtime, such as `~/.vim/plugin` and `~/.vim/autoload`.

## What This Repository Does

`vim9-unite` is responsible for:

- opening the picker window
- rendering the prompt and candidates
- filtering candidates by query
- moving the selection
- calling the selected action callback
- exposing a small UI API to the action callback

It is not responsible for:

- collecting file lists, MRU lists, quickfix entries, etc.
- deciding what an action means
- bundling default picker definitions

## Public API

This repository exposes three main entry points:

- `unite#Register(name, picker)`
- `unite#Start(name, opts = {})`
- `:Unite {name} [args...]`

`plugin/unite.vim` only defines the `:Unite` command. Everything else is expected to be provided by the user side.

## Picker Definition

Register a picker like this:

```vim
call unite#Register('example', {
  source: function('ExampleSource'),
  action: function('ExampleAction'),
})
```

Supported keys:

- `source`
  `source(args, ctx)` must return a list of candidates.
- `action`
  `action(candidate, ctx, api)` is called when the current candidate is selected.
- `syntax`
  Optional UI hint. Currently `line-numbers` is supported.

## Source Function

`source(args, ctx)` receives:

- `args`
  Extra arguments passed from `:Unite`.
- `ctx`
  A dictionary containing picker context.

Current `ctx` values:

- `picker_name`
- `origin_winid`
- `origin_bufnr`
- `options`

It must return a list of candidate dictionaries.

Minimal example:

```vim
def ExampleSource(args: list<any>, ctx: dict<any>): list<dict<any>>
  return [
    {
      word: 'README.md',
      abbr: 'README.md',
      data: { path: 'README.md' },
    },
  ]
enddef
```

Candidate fields:

- `word`
  Base text used for filtering.
- `abbr`
  Optional display text.
- `data`
  Optional arbitrary payload for the action.
- `action`
  Optional candidate-local action. If present, it overrides the picker action.

## Action Function

`action(candidate, ctx, api)` receives:

- `candidate`
  The selected candidate.
- `ctx`
  Execution context.
- `api`
  Small UI control API exposed by the picker core.

Current `ctx` values:

- `picker_name`
- `query`
- `origin_winid`
- `origin_bufnr`
- `picker_winid`
- `picker_bufnr`
- `options`

Current `api` values:

- `close()`
  Close the picker and return focus to the origin window when possible.
- `focus_origin()`
  Move focus back to the origin window without closing the picker.

Example:

```vim
def ExampleAction(candidate: dict<any>, ctx: dict<any>, api: dict<any>)
  api.close()
  execute 'edit ' .. fnameescape(candidate.data.path)
enddef
```

## Minimal Setup

Put registration in your Vim runtime, for example `~/.vim/plugin/unite_example.vim`:

```vim
vim9script

def ExampleSource(args: list<any>, ctx: dict<any>): list<dict<any>>
  return [
    {
      word: expand('%:p'),
      data: { path: expand('%:p') },
    },
  ]
enddef

def ExampleAction(candidate: dict<any>, ctx: dict<any>, api: dict<any>)
  api.close()
  execute 'edit ' .. fnameescape(candidate.data.path)
enddef

unite#Register('current-file', {
  source: function('ExampleSource'),
  action: function('ExampleAction'),
})
```

Then run:

```vim
:Unite current-file
```

## Design Note

The important boundary is:

- this repository provides the picker UI
- your runtime provides picker definitions

If you want file MRU, quickfix, yank history, custom menus, or project-specific actions, they should live outside this repository.
