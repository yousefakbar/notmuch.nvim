let nm = v:lua.require('notmuch')
nmap <buffer> <silent> <CR> :call nm.show_thread()<CR>
nmap <buffer> <silent> q :bwipeout<CR>
nmap <buffer> <silent> % :!mbsync -c $XDG_CONFIG_HOME/isync/mbsyncrc -a && notmuch new<CR>
