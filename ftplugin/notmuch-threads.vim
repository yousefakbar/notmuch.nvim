let nm = v:lua.require('notmuch')
nmap <buffer> <silent> <CR> :call nm.show_thread()<CR>
