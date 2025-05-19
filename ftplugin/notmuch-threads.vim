setlocal nowrap

let nm = v:lua.require('notmuch')
let r = v:lua.require('notmuch.refresh')
let s = v:lua.require('notmuch.sync')
let tag = v:lua.require('notmuch.tag')

command -buffer -range -complete=custom,notmuch#CompTags -nargs=+ TagAdd :call tag.thread_add_tag(<q-args>, <line1>, <line2>)
command -buffer -range -complete=custom,notmuch#CompTags -nargs=+ TagRm :call tag.thread_rm_tag(<q-args>, <line1>, <line2>)
command -buffer -range -complete=custom,notmuch#CompTags -nargs=+ TagToggle :call tag.thread_toggle_tag(<q-args>, <line1>, <line2>)
command -buffer -range DelThread :call tag.thread_add_tag("del", <line1>, <line2>) | :call tag.thread_rm_tag("inbox", <line1>, <line2>)

nmap <buffer> <silent> <CR> :call nm.show_thread()<CR>
nmap <buffer> <silent> r :call r.refresh_search_buffer()<CR>
nmap <buffer> <silent> q :bwipeout<CR>
nmap <buffer> <silent> % :call s.sync_maildir()<CR>
nmap <buffer> + :TagAdd 
xmap <buffer> + :TagAdd 
nmap <buffer> - :TagRm 
xmap <buffer> - :TagRm 
nmap <buffer> = :TagToggle 
xmap <buffer> = :TagToggle 
nmap <buffer> a :TagToggle inbox<CR>j
xmap <buffer> a :TagToggle inbox<CR>
nmap <buffer> A :TagRm inbox unread<CR>j
xmap <buffer> A :TagRm inbox unread<CR>
nmap <buffer> x :TagToggle unread<CR>
xmap <buffer> x :TagToggle unread<CR>
nmap <buffer> f :TagToggle flagged<CR>j
xmap <buffer> f :TagToggle flagged<CR>
nmap <buffer> <silent> C :call v:lua.require('notmuch.send').compose()<CR>
nmap <buffer> dd :DelThread<CR>j
xmap <buffer> d :DelThread<CR>
nmap <buffer> <silent> D :lua require('notmuch.delete').purge_del()<CR>
