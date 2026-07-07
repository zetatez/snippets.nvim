if exists('did_plugin_snippets') || &cp
    finish
endif
let did_plugin_snippets=1

" Load Lua backend - no Python dependency required
if !has('nvim')
   echohl WarningMsg
   echom  "Snippets Lua backend requires Neovim"
   echohl None
   finish
endif

lua require('snippets.init').setup()

" The Commands we define (shadowed by Lua init for completion, but kept for
" Vim 9+ compatibility and :command visibility).
if !exists(':SnippetsEdit')
    command! -bang -nargs=? -complete=customlist,Snippets#FileTypeComplete SnippetsEdit
        \ :call Snippets#Edit(<q-bang>, <q-args>)
endif

if !exists(':SnippetsAddFiletypes')
    command! -nargs=1 SnippetsAddFiletypes :call Snippets#AddFiletypes(<q-args>)
endif

if !exists(':SnippetsRemoveFiletypes')
    command! -nargs=1 SnippetsRemoveFiletypes :call Snippets#RemoveFiletypes(<q-args>)
endif

if !exists(':SnippetsListLocations')
    command! SnippetsListLocations :call Snippets#ListSnippetLocations()
endif

" vim: ts=8 sts=4 sw=4
