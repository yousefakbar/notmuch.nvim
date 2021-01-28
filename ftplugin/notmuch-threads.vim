let nm = v:lua.require('notmuch')
let s = v:lua.require('notmuch.sync')
nmap <buffer> <silent> <CR> :call nm.show_thread()<CR>
nmap <buffer> <silent> r :call nm.refresh_search_buffer()<CR>
nmap <buffer> <silent> q :bwipeout<CR>
nmap <buffer> <silent> % :call s.sync_maildir()<CR>
