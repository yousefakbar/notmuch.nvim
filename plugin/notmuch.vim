command Notmuch :call v:lua.require('notmuch').notmuch_hello()
command -complete=custom,notmuch#CompSearchTerms -nargs=* NmSearch :call v:lua.require('notmuch').search_terms("<args>")

" vim: tabstop=2:shiftwidth=2:expandtab
