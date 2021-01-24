-- General structure of a notmuch-show message:
-- 
--   message
--   ├── header
--   └── body
--       ├── part (ID: x, content:)
--       │   ├── part (ID: z, content:)
--       │   ├── part (ID: u, content:)
--       │   └── part (ID: w, content:)
--       └── part (ID: y, content:)
-- 
-- Therefore, a thread would be essentially a collection of these attributes. In
-- other words, think of a Lua table, where each entry is a `message` table, with
-- the member tables `header` and `body`, and so on until we've captured all the
-- atomic parts of an email message.
-- 
-- The advantage of this approach is that we can encapsulate each message/thread
-- and perform elementary functions on them when displaying/tagging/whatever with
-- them.
-- 
-- Let's say we want to display an entire thread. Grouping the thread into a table
-- of messages gives us top-down control over it. We can dump all messages onto a
-- buffer. We can fold each message because we know their location in the thread.
-- We can decide the indentation (reply-level) of the messages based on the depth
-- level of the message id.

local m = {}
local u = require'notmuch.util'

local function process_message_variables(line)
  m.id = string.match(line, "id:%S+")
  m.depth = string.match(line, "depth:%d+")
  m.match = string.match(line, "match:%S+")
  m.filename = string.match(line, "filename:%C+")
end

local function process_header(tab)
  m.header = {}
  for k,v in pairs(tab) do
    if string.match(v, "^header}$") ~= nil then
      break
    elseif k > 2 then
      table.insert(m.header, v)
    end
  end
end

local function find_body(tab)
  local start = 0
  local last = 0
  for k,v in pairs(tab) do
    if string.match(v, "^body}$") ~= nil then
      u.print_table(tab)
      print(v)
      last = k
      break
    elseif string.match(v, "^body{$") ~= nil then
      start = k
    end
  end
  return { start, last }
end

-- msg is the full message{... ...message} text including the delimiters
m.parse_msg = function(tab)
  process_message_variables(tab[1])
  process_header(tab)
  local body_linenos = find_body(tab)
  u.print_table(body_linenos)
  u.print_table(m.header)
end

return m

-- vim: tabstop=2:shiftwidth=2:expandtab
