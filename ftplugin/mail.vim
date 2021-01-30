set foldmethod=marker

command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagAdd :call v:lua.require('notmuch.tag').msg_add_tag("<args>")
command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagRm :call v:lua.require('notmuch.tag').msg_rm_tag("<args>")
command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagToggle :call tag.msg_toggle_tag("<args>")

nmap <buffer> <silent> U :call v:lua.require('notmuch.attach').get_urls_from_cursor_msg()<CR>
nmap <buffer> <silent> <Tab> zj
nmap <buffer> <silent> <S-Tab> zk
nmap <buffer> <silent> <Enter> za
nmap <buffer> <silent> a :call v:lua.require('notmuch.attach').get_attachments_from_cursor_msg()<CR>
nmap <buffer> <silent> r :call v:lua.require('notmuch').refresh_thread_buffer()<CR>
nmap <buffer> <silent> q :bwipeout<CR>
nmap <buffer> + :TagAdd 
nmap <buffer> - :TagRm 
nmap <buffer> = :TagToggle 
