local c = {}
local u = require'notmuch.util'

local function comp_tags()
  local tags = {}
  local tag_table = u.split(u.capture("notmuch search --output=tags '*'"))
  for k,v in pairs(tag_table) do
    tags[k] = "tag:" .. v
  end
  return tags
end


local function comp_search_terms()
  return { "attachment:", "folder:", "id:", "mimetype:", "property:", "subject:", "thread:", "date:", "from:", "lastmod:", "path:", "query:", "tag:", "to:" }
end

c.complete = function(a, l, p)
  if a:match("tag") == nil then
    return comp_search_terms()
  else
    return comp_tags()
  end
end

return c

-- vim: tabstop=2:shiftwidth=2:expandtab
