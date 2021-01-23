let nm = v:lua.require('notmuch')

command Notmuch :call nm.show_all_tags()
command -complete=customlist,notmuch#CompTags -nargs=* NotmuchSearch :call nm.search_terms("<args>")
