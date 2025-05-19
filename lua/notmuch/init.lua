local nm = {}
local v = vim.api

local config = require('notmuch.config')

-- Setup `notmuch.nvim`
--
-- This function initializes the notmuch.nvim plugin. It defines the entry point
-- command(s) and sets configuration options based on user passed arguments or
-- default values
--
-- @param opts table: Table of options as passed by the user with their config
--                    setup
--
-- @usage
-- -- Example from inside `lazy.nvim` plugin spec configuration
-- {
--   config = function()
--     opts = { ... } -- options go here
--     require('notmuch').setup(opts)
--   end
-- }
nm.setup = function(opts)
  -- Setup configuration defaults and/or user options
  config.setup(opts)

  -- Set up the main entry point command :Notmuch
  vim.cmd[[command Notmuch :lua require('notmuch').notmuch_hello()]]
  vim.cmd[[command Inbox :lua require('notmuch').search_terms("tag:inbox")]]
end

-- Launch `notmuch.nvim` landing page
--
-- This function launches the main entry point of the plugin into your notmuch
-- database. You are greeted with a list of all the tags in your database,
-- available for querying and/or counting. First line contains help hints.
--
-- If buffer is already open from before, it will simply load it as active
--
-- @usage
-- lua require('notmuch').notmuch_hello()
nm.notmuch_hello = function()
  local bufno = vim.fn.bufnr('Tags')
  if bufno ~= -1 then
    v.nvim_win_set_buf(0, bufno)
  else
    nm.show_all_tags() -- Move to tag.lua
  end
  print("Welcome to Notmuch.nvim! Choose a tag to search it.")
end

-- Conducts a `notmuch search` operation
--
-- This function takes a search term, runs the query against your notmuch
-- database **asynchronously** and returns the list of thread results in a
-- buffer for the user to browse
--
-- @param search string: search terms matching format from
--                       `notmuch-search-terms(7)`
-- @param jumptothreadid string: jump to thread id after search
--
-- @usage
-- lua require('notmuch').search_terms('tag:inbox')
nm.search_terms = function(search, jumptothreadid)
  local num_threads_found = 0
  if search == '' then
    return nil
  elseif string.match(search, '^thread:%S+$') ~= nil then
    nm.show_thread(search)
    return true
  end
  local bufno = vim.fn.bufnr(search)
  if bufno ~= -1 then
    v.nvim_win_set_buf(0, bufno)
    return true
  end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, search)
  v.nvim_win_set_buf(0, buf)

  local hint_text = "Hints: <Enter>: Open thread | q: Close | r: Refresh | %: Sync maildir | a: Archive | A: Archive and Read | +: Add tag | -: Remove tag | =: Toggle tag"
  v.nvim_buf_set_lines(buf, 0, 2, false, { hint_text , "" })

  -- Async notmuch search to make the UX non blocking
  require('notmuch.async').run_notmuch_search(search, buf, function()
    -- Completion logic
    if vim.fn.getline(2) ~= '' then num_threads_found = vim.fn.line('$') - 1 end
    print('Found ' .. num_threads_found .. ' threads')
    vim.fn.search(jumptothreadid)
  end)

  -- Set cursor at head of buffer, declare filetype, and disable modifying
  v.nvim_win_set_cursor(0, { 1, 0 })
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-threads"
  vim.bo.modifiable = false
end

--- Opens a thread in the mail view with all messages in the thread
--
-- This function fetches all the messages in the input thread's ID from the
-- notmuch database and displays them in the mail.vim view.
--
-- @param s string: The string to fetch the threadid from (individual line, or
--                  thread full form)
-- @return true|nil: `true` for successful display, nil for any error
--
-- @usage
-- nm.show_thread("thread:00000000000003aa")
-- nm.show_thread(vim.api.nvim_get_current_line())
nm.show_thread = function(s)
  -- Fetch the threadid from the input `s` or from current line
  local threadid = ''
  if s == nil then
    -- fetch from the current line since no input passed
    local line = v.nvim_get_current_line()
    if line:find("Hints:") == 1 then
      -- Skip if selected the Hints line
      print("Cannot open Hints :-)")
      return nil
    end
    threadid = string.match(line, "[0-9a-z]+", 7)
  else
    threadid = string.match(s, "[0-9a-z]+", 7)
  end

  -- Open buffer if already exists, otherwise create new `buf`
  local bufno = vim.fn.bufnr('thread:' .. threadid)
  if bufno ~= -1 then
    v.nvim_win_set_buf(0, bufno)
    return true
  end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "thread:" .. threadid)
  v.nvim_win_set_buf(0, buf)
  v.nvim_command("silent 0read! notmuch show --exclude=false thread:" .. threadid .. " | col")

  -- Clean up the messages in the thread to display in UI friendly way
  require('notmuch.util').process_msgs_in_thread(buf)

  -- Insert hint message at the top of the buffer
  local hint_text = "Hints: <Enter>: Toggle fold message | <Tab>: Next message | <S-Tab>: Prev message | q: Close | a: See attachment parts"
  v.nvim_buf_set_lines(buf, 0, 0, false, { hint_text , "" })

  -- Place cursor at head of buffer and prepare display and disable modification
  v.nvim_buf_set_lines(buf, -3, -1, true, {})
  v.nvim_win_set_cursor(0, { 1, 0})
  vim.bo.filetype="mail"
  vim.bo.modifiable = false
end

-- Counts the number of threads matching the search terms
--
-- This function runs a search query in your `notmuch` database against the
-- argument search terms and returns the number of threads which match
--
-- @param search string: search terms matching format from
--                       `notmuch-search-terms(7)`
--
-- @usage
-- lua require('notmuch').count('tag:inbox') -- > '999'
nm.count = function(search)
  local db = require'notmuch.cnotmuch'(config.options.notmuch_db_path, 0)
  local q = db.create_query(search)
  local count_threads = q.count_threads()
  db.close()
  return "[" .. search .. "]: " .. count_threads .. " threads"
end

--- Opens the landing/homepage for Notmuch: the `hello` page
--
-- This function opens the main landing page for `notmuch.nvim`. It essentially
-- consists of all the tags in the `notmuch` database for the user to select or
-- count. They can also search from here etc.
--
-- @usage
-- nm.show_all_tags() -- opens the `hello` page
nm.show_all_tags = function()
  -- Fetch all tags available in the notmuch database
  local db = require'notmuch.cnotmuch'(config.options.notmuch_db_path, 0)
  local tags = db.get_all_tags()
  db.close()

  -- Create dedicated buffer. Content is fetched using `db.get_all_tags()`
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "Tags")
  v.nvim_win_set_buf(0, buf)
  v.nvim_buf_set_lines(buf, 0, 0, true, tags)

  -- Insert help hints at the top of the buffer
  local hint_text = "Hints: <Enter>: Show threads | q: Close | r: Refresh | %: Refresh maildir | c: Count messages"
  v.nvim_buf_set_lines(buf, 0, 0, false, { hint_text , "" })

  -- Clean up the buffer and set the cursor to the head
  v.nvim_win_set_cursor(0, { 3, 0})
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-hello"
  vim.bo.modifiable = false
end

return nm

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
