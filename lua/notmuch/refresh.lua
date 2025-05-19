local r = {}
local v = vim.api
local nm = require('notmuch')

-- Refreshes the search results buffer
--
-- This function refreshes the buffer showing the results of a search (list of
-- threads) by deleting the original buffer and re-invokes the `search_terms()`
-- function.
--
-- @usage
-- -- Normally invoked by pressing `r` in the search results buffer
-- lua require('notmuch.refresh').refresh_search_buffer()
r.refresh_search_buffer = function()
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, "%S+", 8)
  local search = string.match(v.nvim_buf_get_name(0), '%a+:%C+')
  v.nvim_command('bwipeout')
  nm.search_terms(search, threadid)
  vim.fn.search(threadid)
end

-- Refreshes the thread view buffer
--
-- This function refreshes the buffer containing a thread view with all its
-- messages inside by deleting the original buffer and re-invokes the
-- `show_thread()` function again to refresh the thread view.
--
-- @usage
-- -- Normally invoked by pressing `r` in the thread view buffer
-- lua require('notmuch.refresh').refresh_thread_buffer()
r.refresh_thread_buffer = function()
  local thread = string.match(v.nvim_buf_get_name(0), 'thread:%C+')
  v.nvim_command('bwipeout')
  nm.show_thread(thread)
end

-- Refreshes the notmuch landing page buffer
--
-- This function refreshes the `notmuch-hello` landing page buffer by deleting
-- the original buffer (wipeout to flush it from memory) and invokes the
-- `show_all_tags()` function again. This is useful when you know changes have
-- been made to the buffer contents and want to reflect it accordingly
--
-- @usage
-- -- Normally invoked by pressing `r` in the Tags buffer
-- lua require('notmuch.refresh').refresh_hello_buffer()
r.refresh_hello_buffer = function()
  v.nvim_command('bwipeout')
  nm.show_all_tags()
end

return r
