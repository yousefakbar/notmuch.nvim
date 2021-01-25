command Notmuch :call v:lua.require('notmuch').show_all_tags()
command -complete=custom,notmuch#CompTags -nargs=* NmSearch :call v:lua.require('notmuch').search_terms("<args>")

" vim: tabstop=2:shiftwidth=2:expandtab
