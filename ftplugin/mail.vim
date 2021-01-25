set foldmethod=marker

nmap <buffer> <silent> q :bwipeout<CR>
nmap <buffer> <silent> a :call v:lua.require('notmuch.attach').get_attachments_from_id(getline('.'))<CR>
