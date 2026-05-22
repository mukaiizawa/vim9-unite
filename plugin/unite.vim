vim9script

if exists('g:loaded_unite')
  finish
endif

command! -nargs=+ Unite call unite#StartCommand(<q-args>)

def TrackFileBuffer()
  if bufnr('%') != str2nr(expand('<abuf>')) || empty(expand('<amatch>'))
    return
  endif
  unite#file#AppendCurrent()
enddef

def TrackRepoBuffer()
  if bufnr('%') != str2nr(expand('<abuf>')) || empty(expand('<amatch>'))
    return
  endif
  unite#repo#AppendCurrent()
enddef

augroup unite_file
  autocmd!
  autocmd BufEnter,VimEnter,BufWinEnter * call TrackFileBuffer()
  autocmd VimLeavePre * call unite#file#Save({event: 'VimLeavePre'})
augroup END

if !unite#store#IsSudo()
  augroup unite_repo
    autocmd!
    autocmd BufEnter,VimEnter,BufWinEnter * call TrackRepoBuffer()
    autocmd VimLeavePre * call unite#repo#Save()
  augroup END
endif

augroup unite_yank
  autocmd!
  if exists('##TextYankPost')
    autocmd FocusGained,FocusLost * silent call unite#yank#Append()
    autocmd TextYankPost * silent call unite#yank#YankPost()
  else
    autocmd CursorMoved,FocusGained,FocusLost,VimLeavePre * silent call unite#yank#Append()
    autocmd TextChanged * silent call unite#yank#Append()
  endif
augroup END

g:loaded_unite = 1
