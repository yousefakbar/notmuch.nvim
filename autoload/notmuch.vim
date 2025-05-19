let s:search_terms_list = [ "attachment:", "folder:", "id:", "mimetype:",
      \ "property:", "subject:", "thread:", "date:", "from:", "lastmod:",
      \ "path:", "query:", "tag:", "is:", "to:", "body:", "and ", "or ", "not " ]

function! notmuch#CompSearchTerms(ArgLead, CmdLine, CursorPos) abort
  if match(a:ArgLead, "tag:") != -1
    let l:tag_list = split(system('notmuch search --output=tags "*"'), '\n')
    return "tag:" .. join(l:tag_list, "\ntag:")
  endif
  if match(a:ArgLead, "is:") != -1
    let l:is_list = split(system('notmuch search --output=tags "*"'), '\n')
    return "is:" .. join(l:is_list, "\nis:")
  endif
  if match(a:ArgLead, "mimetype:") != -1
    let l:mimetype_list = ["application/", "audio/", "chemical/",
          \ "font/", "image/", "inode/", "message/", "model/",
          \ "multipart/", "text/", "video/"]
    return "mimetype:" .. join(l:mimetype_list, "\nmimetype:")
  endif
  if match(a:ArgLead, "from:") != -1
    let l:from_list = split(system('notmuch address "*"'), '\n')
    return "from:" .. join(l:from_list, "\nfrom:")
  endif
  if match(a:ArgLead, "to:") != -1
    let l:to_list = split(system('notmuch address "*"'), '\n')
    return "to:" .. join(l:to_list, "\nto:")
  endif
  if match(a:ArgLead, "folder:") != -1
    let l:folder_list = split(system('find ' .. g:notmuch_mailroot .. ' -type d -name cur -print0| sed -n -z "s|^' .. g:notmuch_mailroot .. '/*||p" | xargs -0 dirname | sort | uniq'), '\n')
    return "folder:" .. join(l:folder_list, "\nfolder:")
  endif
  if match(a:ArgLead, "path:") != -1
    let l:path_list = split(system('find ' .. g:notmuch_mailroot .. ' -type d -print0| sed -n -z "s|^' .. g:notmuch_mailroot .. '/*||p" | sort -z | uniq -z | tr "\0" "\n"'), '\n')
    return "path:" .. join(l:path_list, "\npath:")
  endif
  return join(s:search_terms_list, "\n")
endfunction

function! notmuch#CompTags(ArgLead, CmdLine, CursorPos) abort
  return system('notmuch search --output=tags "*"')
endfunction

function! notmuch#CompAddress(ArgLead, CmdLine, CursorPos) abort
  return system('notmuch address "*"')
endfunction
" vim: tabstop=2:shiftwidth=2:expandtab
