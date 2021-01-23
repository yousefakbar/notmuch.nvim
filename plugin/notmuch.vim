let nm = v:lua.require('notmuch')
command -nargs=* NmSearchTag :call nm.search_tag("<args>")
