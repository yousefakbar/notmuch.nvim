let attach = v:lua.require('notmuch.attach')
nnoremap <buffer> <silent> q :bwipeout<CR>
nnoremap <buffer> <silent> s :call attach.save_attachment_part()<CR>
nnoremap <buffer> <silent> v :call attach.view_attachment_part()<CR>
