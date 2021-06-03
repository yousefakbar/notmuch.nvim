" welcome screen displaying all tags available to search
let nm = v:lua.require('notmuch')
let s = v:lua.require('notmuch.sync')
nmap <buffer> <silent> <CR> :call nm.search_terms("tag:" .. getline('.'))<CR>
nmap <buffer> <silent> c :echo nm.count("tag:" .. getline('.'))<CR>
nmap <buffer> <silent> q :bwipeout<CR>
nmap <buffer> <silent> r :call nm.refresh_hello_buffer()<CR>
nmap <buffer> <silent> % :call s.sync_maildir()<CR>
