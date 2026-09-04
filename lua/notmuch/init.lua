local nm = {}
local v = vim.api

local config = require("notmuch.config")

-- Setup `notmuch.nvim`
--
-- This function initializes the notmuch.nvim plugin. It defines the entry point
-- command(s) and sets configuration options based on user passed arguments or
-- default values
--
---@param opts? table User configuration overrides passed to setup.
--
---@usage
-- -- Example from inside `lazy.nvim` plugin spec configuration
-- {
--   config = function()
--     opts = { ... } -- options go here
--     require('notmuch').setup(opts)
--   end
-- }
nm.setup = function(opts)
  -- Setup configuration defaults and/or user options
  local success = config.setup(opts)

  if not success then
    return
  end

  -- setup user commands
  vim.api.nvim_create_user_command("Notmuch", nm.notmuch_hello, {
    desc = "notmuch.nvim landing page",
  })
  vim.api.nvim_create_user_command("Inbox", function(arg)
    if #arg.fargs ~= 0 then
      require("notmuch").search_terms("tag:inbox to:" .. arg.args)
    else
      require("notmuch").search_terms("tag:inbox")
    end
  end, {
    desc = "Open inbox",
    nargs = "?",
    complete = require("notmuch.completion").comp_address,
  })
  vim.api.nvim_create_user_command("NmSearch", function(arg)
    nm.search_terms(arg.args)
  end, {
    desc = "Notmuch search",
    nargs = "*",
    complete = require("notmuch.completion").comp_search_terms,
  })
  vim.api.nvim_create_user_command("ComposeMail", function(arg)
    require("notmuch.send").compose(arg.args)
  end, {
    desc = "Compose mail",
    nargs = "*",
    complete = require("notmuch.completion").comp_address,
  })
  vim.api.nvim_create_user_command("NotmuchDrafts", function()
    require("notmuch.send").select_draft()
  end, {
    desc = "Select and open drafts",
  })
end

-- Launch `notmuch.nvim` landing page
--
-- This function launches the main entry point of the plugin into your notmuch
-- database. You are greeted with a list of all the tags in your database,
-- available for querying and/or counting. First line contains help hints.
--
-- If buffer is already open from before, it will simply load it as active
--
---@usage
-- lua require('notmuch').notmuch_hello()
nm.notmuch_hello = function()
  local bufno = vim.fn.bufnr("Tags")
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
---@param search string Search terms matching `notmuch-search-terms(7)`.
---@param jumptothreadid? string Thread id to jump to after results load.
--
---@usage
-- lua require('notmuch').search_terms('tag:inbox')
nm.search_terms = function(search, jumptothreadid)
  local num_threads_found = 0
  if search == "" then
    return nil
  elseif string.match(search, "^thread:%S+$") ~= nil then
    nm.show_thread(search)
    return true
  end
  -- Use exact match for buffer name to avoid partial matches
  -- Escape special regex characters in the search term
  local escaped_search = vim.fn.escape(search, "^$.*~[]\\")
  local bufno = vim.fn.bufnr("^" .. escaped_search .. "$")
  if bufno ~= -1 then
    -- Buffer exists, switch to it without refreshing
    -- This preserves cursor position and navigation state
    -- Users can press 'r' to explicitly refresh if needed
    v.nvim_win_set_buf(0, bufno)
    return true
  end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, search)
  v.nvim_win_set_buf(0, buf)

  local hint_text =
    "Hints: <Enter>: Open thread | q: Close | r: Refresh | %: Sync maildir | a: Archive | A: Archive and Read | +/-/=: Add, remove, toggle tag | o: Sort | dd: Delete"
  v.nvim_buf_set_lines(buf, 0, 2, false, { hint_text, "" })

  -- Async notmuch search to make the UX non blocking
  require("notmuch.async").run_notmuch_search(search, buf, function()
    -- Check if buffer is still valid (might have been deleted during refresh)
    if not v.nvim_buf_is_valid(buf) then
      return
    end
    -- Completion logic
    local line_count = v.nvim_buf_line_count(buf)
    if line_count > 1 then
      num_threads_found = line_count - 1
    end
    print("Found " .. num_threads_found .. " threads")
    vim.fn.search(jumptothreadid)
  end)

  -- Set cursor at head of buffer, declare filetype, and disable modifying
  v.nvim_win_set_cursor(0, { 1, 0 })
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-threads"
  vim.bo.modifiable = false
end

--- Reverses the threads sorting in `notmuch-threads` buffer
--
-- This function reverses the lines of the `notmuch-threads` buffer which result
-- from the `search_terms()` function. It effectively toggles the sorting of
-- these threads between newest-first and oldest-first.
--
-- We do this instantly instead of running `notmuch search --sort` to save time
-- especially when it comes to large results with thousands of thread.
nm.reverse_sort_threads = function()
  -- Get all lines, disregarding top-level hints line
  local lines = v.nvim_buf_get_lines(0, 0, -1, false)
  local hints = table.remove(lines, 1)

  -- Reverse lines
  local reversed = {}
  for i = #lines, 1, -1 do
    table.insert(reversed, lines[i])
  end

  -- Re-attach hints line
  table.insert(reversed, 1, hints)

  -- Replace lines in buffer
  vim.bo.modifiable = true
  v.nvim_buf_set_lines(0, 0, -1, false, reversed)
  vim.bo.modifiable = false
end

--- Position the cursor on the first message and apply the configured fold policy.
local function apply_thread_open_behavior()
  local messages = vim.b.notmuch_messages
  local first_msg = messages and messages[1]
  local fold_line = first_msg and first_msg.fold_line
  local line_count = v.nvim_buf_line_count(0)
  local has_valid_fold = type(fold_line) == "number" and fold_line >= 1 and fold_line <= line_count
  local position = has_valid_fold and fold_line or 1

  v.nvim_win_set_cursor(0, { position, 0 })

  if not has_valid_fold then
    return
  end

  local mode = config.options.thread_auto_expand
  if mode == "first" and vim.fn.foldclosed(position) ~= -1 then
    vim.cmd("normal! zo")
  elseif mode == "all" then
    vim.cmd("normal! zR")
  end
end

--- Opens a thread in the mail view with all messages in the thread
--
-- This function fetches all the messages in the input thread's ID from the
-- notmuch database and displays them in the mail.vim view.
--
---@param s? string Thread id/search-result line to extract the thread id from; defaults to the current line.
---@return true|nil reused_buffer True when an existing thread buffer was reused; nil otherwise.
--
---@usage
-- nm.show_thread("thread:00000000000003aa")
-- nm.show_thread(vim.api.nvim_get_current_line())
nm.show_thread = function(s)
  -- Fetch the threadid from the input `s` or from current line
  local threadid = ""
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
  local bufno = vim.fn.bufnr("thread:" .. threadid)
  if bufno ~= -1 then
    v.nvim_win_set_buf(0, bufno)
    apply_thread_open_behavior()
    return true
  end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "thread:" .. threadid)
  v.nvim_win_set_buf(0, buf)

  -- Get output (JSON parsed) and display lines in buffer
  local lines, metadata = require("notmuch.thread").show_thread(threadid)
  v.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Set up buffer-local variables with thread metadata
  vim.b.notmuch_thread = metadata.thread
  vim.b.notmuch_messages = metadata.messages

  -- Insert hint message at the top of the buffer
  local hint_text =
    "Hints: <Enter>: Toggle fold message | <Tab>: Next message | <S-Tab>: Prev message | q: Close | a: See attachment parts"
  v.nvim_buf_set_lines(buf, 0, 0, false, { hint_text, "" })

  -- Prepare display, disable modification, and apply initial thread behavior
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "mail"
  vim.bo.modifiable = false
  apply_thread_open_behavior()

  -- Set up cursor tracking for updating vim.b.notmuch_current
  require("notmuch.thread").setup_cursor_tracking(buf)
end

-- Counts the number of threads matching the search terms
--
-- This function runs a search query in your `notmuch` database and returns a
-- human-readable summary string with the matching thread count.
--
---@param search string Search terms matching `notmuch-search-terms(7)`.
---@return string summary Formatted count summary.
--
---@usage
-- lua require('notmuch').count('tag:inbox') -- > '[tag:inbox]: 999 threads'
nm.count = function(search)
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 0)
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
---@usage
-- nm.show_all_tags() -- opens the `hello` page
nm.show_all_tags = function()
  -- Fetch all tags available in the notmuch database
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 0)
  local tags = db.get_all_tags()
  db.close()
  local queries = config.options.queries or {}

  -- Build buffer content.  We track which 1-indexed lines hold query entries
  -- so the <Enter> handler can dispatch to the right search term.
  local all_lines = {}
  local saved_query_map = {} -- 1-indexed buffer line → query string

  if #queries > 0 then
    table.insert(all_lines, "Saved/Pinned:")
    table.insert(all_lines, "-------------")
    for _, q in ipairs(queries) do
      table.insert(all_lines, "  " .. q.name .. " -- `" .. q.query .. "`")
    end
    table.insert(all_lines, "")
    table.insert(all_lines, "Tags:")
    table.insert(all_lines, "-----")
  end

  for _, tag in ipairs(tags) do
    table.insert(all_lines, tag)
  end

  -- Create dedicated buffer
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "Tags")
  v.nvim_win_set_buf(0, buf)
  v.nvim_buf_set_lines(buf, 0, 0, true, all_lines)

  -- Insert help hints at the top of the buffer (prepended, so all_lines shifts by 2)
  local hint_text =
    "Hints: <Enter>: Show threads | q: Close | r: Refresh | %: Refresh maildir | c: Count messages"
  v.nvim_buf_set_lines(buf, 0, 0, false, { hint_text, "" })

  -- After prepending two lines (hints + blank), all_lines[i] is now buffer line (i+2).
  -- Saved queries begin at all_lines[3] (1-indexed within all_lines) → buffer line 5.
  --   all_lines[1] = "Saved/Pinned:"  → buffer line 3
  --   all_lines[2] = "-------------"  → buffer line 4
  --   all_lines[2+j] = queries[j]     → buffer line 4+j   (j = 1..#queries)
  if #queries > 0 then
    for j, q in ipairs(queries) do
      saved_query_map[4 + j] = q.query
    end
  end
  vim.b.notmuch_saved_queries = saved_query_map

  -- Place cursor on first actionable line
  local first_line = #queries > 0 and 5 or 3
  v.nvim_win_set_cursor(0, { first_line, 0 })
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-hello"
  vim.bo.modifiable = false
end

--- Handles `c` (count) on the notmuch-hello dashboard
--
-- Resolves the query for the current line the same way as open_hello_line():
-- saved/pinned entries use their stored query; plain tag lines use "tag:<name>".
-- Header, separator, and blank lines are silently ignored.
--
---@usage  called by ftplugin/notmuch-hello.vim via c
nm.count_hello_line = function()
  local lnum = vim.fn.line(".")
  local query_map = vim.b.notmuch_saved_queries or {}

  -- If on line 1 (hints line) then do nothing
  if lnum == 1 then
    return
  end

  local query
  if query_map[lnum] and query_map[lnum] ~= vim.NIL then
    query = query_map[lnum]
  else
    local line = v.nvim_get_current_line()
    if line == "" or line:match("^%s*%-+%s*$") or line:match("^%u%a*.*:$") then
      return
    end
    query = "tag:" .. line
  end

  vim.notify(nm.count(query), vim.log.levels.INFO)
end

--- Handles <Enter> on the notmuch-hello dashboard
--
-- Lines inside the Saved/Pinned section carry a raw query string stored in
-- `vim.b.notmuch_saved_queries` (keyed by 1-indexed line number).  All other
-- actionable lines are bare tag names and are searched with "tag:<name>".
-- Header, separator, and blank lines are silently ignored.
--
---@usage  called by ftplugin/notmuch-hello.vim via <CR>
nm.open_hello_line = function()
  local lnum = vim.fn.line(".")
  local query_map = vim.b.notmuch_saved_queries or {}

  -- If on line 1 (hints line) then do nothing
  if lnum == 1 then
    return
  end

  if query_map[lnum] and query_map[lnum] ~= vim.NIL then
    -- Saved/pinned query line
    nm.search_terms(query_map[lnum])
    return
  end

  local line = v.nvim_get_current_line()

  -- Skip non-actionable lines: blank, separator ("---"), section headers ("Word:")
  if line == "" or line:match("^%s*%-+%s*$") or line:match("^%u%a*.*:$") then
    return
  end

  -- Regular tag line
  nm.search_terms("tag:" .. line)
end

return nm

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
