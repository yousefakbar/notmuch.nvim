setlocal nowrap

let nm = v:lua.require('notmuch')
let r = v:lua.require('notmuch.refresh')
let s = v:lua.require('notmuch.sync')
let tag = v:lua.require('notmuch.tag')

command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagAdd :call tag.thread_add_tag("<args>")
command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagRm :call tag.thread_rm_tag("<args>")
command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagToggle :call tag.thread_toggle_tag("<args>")

nnoremap <buffer> <silent> <CR> :call nm.show_thread()<CR>
nnoremap <buffer> <silent> r :call r.refresh_search_buffer()<CR>
nnoremap <buffer> <silent> q :bwipeout<CR>
nnoremap <buffer> <silent> % :call s.sync_maildir()<CR>
nnoremap <buffer> + :TagAdd 
nnoremap <buffer> - :TagRm 
nnoremap <buffer> = :TagToggle 
nnoremap <buffer> a :TagToggle inbox<CR>j
nnoremap <buffer> A :TagRm inbox unread<CR>j
nnoremap <buffer> x :TagToggle unread<CR>j
nnoremap <buffer> <silent> C :call v:lua.require('notmuch.send').compose()<CR>
