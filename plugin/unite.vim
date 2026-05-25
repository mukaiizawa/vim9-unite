vim9script

if exists('g:loaded_unite')
  finish
endif

command! -nargs=+ Unite call unite#StartCommand(<q-args>)

g:loaded_unite = 1
