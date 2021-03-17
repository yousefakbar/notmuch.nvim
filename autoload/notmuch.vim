let s:search_terms_list = [ "attachment:", "folder:", "id:", "mimetype:",
      \ "property:", "subject:", "thread:", "date:", "from:", "lastmod:",
      \ "path:", "query:", "tag:", "to:" ]

function! notmuch#CompSearchTerms(ArgLead, CmdLine, CursorPos) abort
  if match(a:ArgLead, "tag:") != -1
    let l:tag_list = split(system('notmuch search --output=tags "*"'), '\n')
    return "tag:" .. join(l:tag_list, "\ntag:")
  endif
  return join(s:search_terms_list, "\n")
endfunction

function! notmuch#CompTags(ArgLead, CmdLine, CursorPos) abort
  return system('notmuch search --output=tags "*"')
endfunction

" vim: tabstop=2:shiftwidth=2:expandtab
