let g:notmuch_mailroot = trim(system('notmuch config get database.mail_root'))
command -complete=custom,notmuch#CompSearchTerms -nargs=* NmSearch :call v:lua.require('notmuch').search_terms(<q-args>)
command -complete=custom,notmuch#CompAddress -nargs=* ComposeMail :call v:lua.require('notmuch.send').compose(<q-args>)

" vim: tabstop=2:shiftwidth=2:expandtab
