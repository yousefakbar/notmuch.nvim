setlocal nowrap

let nm = v:lua.require('notmuch')
let s = v:lua.require('notmuch.sync')
let tag = v:lua.require('notmuch.tag')

command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagAdd :call tag.thread_add_tag("<args>")
command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagRm :call tag.thread_rm_tag("<args>")

nmap <buffer> <silent> <CR> :call nm.show_thread()<CR>
nmap <buffer> <silent> r :call nm.refresh_search_buffer()<CR>
nmap <buffer> <silent> q :bwipeout<CR>
nmap <buffer> <silent> % :call s.sync_maildir()<CR>
nmap <buffer> + :TagAdd 
nmap <buffer> - :TagRm 
