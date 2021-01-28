set foldmethod=marker

nmap <buffer> <silent> <Tab> zj
nmap <buffer> <silent> <S-Tab> zk
nmap <buffer> <silent> <Enter> za
nmap <buffer> <silent> a :call v:lua.require('notmuch.attach').get_attachments_from_cursor_msg()<CR>
nmap <buffer> <silent> r :call v:lua.require('notmuch').refresh_thread_buffer()<CR>
nmap <buffer> <silent> q :bwipeout<CR>
