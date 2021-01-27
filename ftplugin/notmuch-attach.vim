let attach = v:lua.require('notmuch.attach')
nmap <buffer> <silent> q :bwipeout<CR>
nmap <buffer> <silent> s :call attach.save_attachment_part()<CR>
nmap <buffer> <silent> v :call attach.view_attachment_part()<CR>
