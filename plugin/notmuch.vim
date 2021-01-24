let nm = v:lua.require('notmuch')

command Notmuch :call nm.show_all_tags()
command -complete=custom,notmuch#CompTags -nargs=* NmSearch :call nm.search_terms("<args>")

" vim: tabstop=2:shiftwidth=2:expandtab
