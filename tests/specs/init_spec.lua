local H = dofile("tests/helpers.lua")

local function buffer_basename()
  return vim.api.nvim_buf_get_name(0):match("([^/]+)$") or ""
end

return {
  {
    name = "notmuch_hello reuses existing Tags buffer and leaves it non-modifiable",
    run = function()
      local nm = require("notmuch")
      nm.notmuch_hello()
      local first = vim.api.nvim_get_current_buf()
      vim.cmd("enew")
      nm.notmuch_hello()
      H.eq(first, vim.api.nvim_get_current_buf())
      H.eq("Tags", buffer_basename())
      H.eq(false, vim.bo.modifiable)
      H.eq(3, vim.api.nvim_win_get_cursor(0)[1])
    end,
  },
  {
    name = "Inbox command searches inbox with optional recipient and address completion",
    run = function()
      local nm = require("notmuch")
      local old_search_terms = nm.search_terms
      local calls = {}
      local ok, err = pcall(function()
        nm.search_terms = function(query)
          table.insert(calls, query)
        end

        vim.cmd("Inbox")
        H.eq("tag:inbox", calls[#calls])

        vim.cmd("Inbox user+tag@example.co.uk")
        H.eq("tag:inbox to:user+tag@example.co.uk", calls[#calls])

        local completions = vim.fn.getcompletion("Inbox ", "cmdline")
        H.ok(#completions > 0, "expected Inbox command address completions")
        H.ok(
          vim.tbl_contains(completions, "Keith Packard <keithp@keithp.com>"),
          "expected notmuch address completion"
        )
      end)
      nm.search_terms = old_search_terms
      if not ok then
        error(err, 0)
      end
    end,
  },
  {
    name = "search_terms returns on empty query without creating a search buffer",
    run = function()
      vim.cmd("enew")
      local before = vim.api.nvim_get_current_buf()
      local result = require("notmuch").search_terms("")
      H.eq(nil, result)
      H.eq(before, vim.api.nvim_get_current_buf())
      H.eq("", buffer_basename())
    end,
  },
  {
    name = "search_terms opens thread:<id> queries directly in thread view",
    run = function()
      local id = H.first_thread_id("tag:inbox")
      local result = require("notmuch").search_terms("thread:" .. id)
      H.eq(true, result)
      H.eq("thread:" .. id, buffer_basename())
      H.eq("mail", vim.bo.filetype)
    end,
  },
  {
    name = "search_terms names, reuses, and keeps thread buffers non-modifiable",
    run = function()
      local query = "tag:inbox and tag:unread"
      require("notmuch").search_terms(query)
      H.wait_until(function()
        return table.concat(H.current_lines(), "\n"):find("thread:", 1, true)
      end, 3000)
      local first = vim.api.nvim_get_current_buf()
      H.eq(query, buffer_basename())
      H.eq(false, vim.bo.modifiable)
      H.eq(1, vim.api.nvim_win_get_cursor(0)[1])
      vim.cmd("enew")
      H.eq(true, require("notmuch").search_terms(query))
      H.eq(first, vim.api.nvim_get_current_buf())
    end,
  },
  {
    name = "search_terms jumps to requested thread after async refresh completes",
    run = function()
      local query = "tag:inbox"
      local target = H.first_thread_id(query)
      require("notmuch").search_terms(query .. " and thread:" .. target, target)
      H.wait_until(function()
        return vim.api.nvim_get_current_line():find(target, 1, true)
      end, 3000)
      H.contains(vim.api.nvim_get_current_line(), target)
    end,
  },
  {
    name = "reverse_sort_threads preserves hints and reverses result lines",
    run = function()
      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.bo.modifiable = true
      vim.api.nvim_buf_set_lines(
        buf,
        0,
        -1,
        false,
        { "Hints: keep", "thread:1", "thread:2", "thread:3" }
      )
      vim.bo.filetype = "notmuch-threads"
      require("notmuch").reverse_sort_threads()
      H.same({ "Hints: keep", "thread:3", "thread:2", "thread:1" }, H.current_lines())
      H.eq(false, vim.bo.modifiable)
    end,
  },
  {
    name = "reverse_sort_threads handles empty and one-result buffers",
    run = function()
      local nm = require("notmuch")
      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.bo.modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Hints: keep" })
      vim.bo.filetype = "notmuch-threads"
      nm.reverse_sort_threads()
      H.same({ "Hints: keep" }, H.current_lines())
      H.eq(false, vim.bo.modifiable)

      vim.bo.modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Hints: keep", "thread:only" })
      vim.bo.modifiable = false
      nm.reverse_sort_threads()
      H.same({ "Hints: keep", "thread:only" }, H.current_lines())
      H.eq(false, vim.bo.modifiable)
    end,
  },
  {
    name = "show_thread extracts selected thread id, renders lines, hints, metadata, and tracking",
    run = function()
      local nm = require("notmuch")
      local thread = require("notmuch.thread")
      local old_show_thread = thread.show_thread
      local old_setup_cursor_tracking = thread.setup_cursor_tracking
      local called_id, tracked_buf

      local ok, err = pcall(function()
        thread.show_thread = function(threadid)
          called_id = threadid
          return { "Rendered header", "id:m1 {{{", "body", "}}}", "" }, {
            thread = { id = threadid, subject = "Rendered subject" },
            messages = { { id = "m1", start_line = 3, end_line = 6 } },
          }
        end
        thread.setup_cursor_tracking = function(buf)
          tracked_buf = buf
        end

        local search_buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, search_buf)
        vim.api.nvim_buf_set_lines(
          search_buf,
          0,
          -1,
          false,
          { "Hints: test", "thread:abc123 rendered subject" }
        )
        vim.api.nvim_win_set_cursor(0, { 2, 0 })

        H.eq(nil, nm.show_thread())
        local thread_buf = vim.api.nvim_get_current_buf()
        H.eq("abc123", called_id)
        H.eq("thread:abc123", buffer_basename())
        H.eq("mail", vim.bo.filetype)
        H.eq(false, vim.bo.modifiable)
        H.eq(thread_buf, tracked_buf)
        H.same({
          "Hints: <Enter>: Toggle fold message | <Tab>: Next message | <S-Tab>: Prev message | q: Close | a: See attachment parts",
          "",
          "Rendered header",
          "id:m1 {{{",
          "body",
          "}}}",
        }, H.current_lines())
        H.eq("abc123", vim.b.notmuch_thread.id)
        H.eq("m1", vim.b.notmuch_messages[1].id)
      end)

      thread.show_thread = old_show_thread
      thread.setup_cursor_tracking = old_setup_cursor_tracking
      if not ok then
        error(err, 0)
      end
    end,
  },
  {
    name = "show_thread refuses the hints line and reuses existing thread buffer",
    run = function()
      local nm = require("notmuch")
      local id = H.first_thread_id("tag:inbox")
      nm.show_thread("thread:" .. id)
      local first = vim.api.nvim_get_current_buf()
      nm.show_thread("thread:" .. id)
      H.eq(first, vim.api.nvim_get_current_buf())

      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Hints: nope" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      H.eq(nil, nm.show_thread())
    end,
  },
}
