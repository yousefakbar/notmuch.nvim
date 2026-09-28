local H = dofile("tests/helpers.lua")

local function with_mock_notmuch(overrides, fn)
  local nm = require("notmuch")
  local old = {}
  for key, value in pairs(overrides) do
    old[key] = nm[key]
    nm[key] = value
  end

  local ok, err = pcall(fn)

  for key, value in pairs(old) do
    nm[key] = value
  end

  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "refresh.refresh_search_buffer delegates to structured in-place refresh",
    run = function()
      local search = require("notmuch.search")
      local old = search.refresh
      local called = false
      search.refresh = function()
        called = true
      end
      require("notmuch.refresh").refresh_search_buffer()
      search.refresh = old
      H.eq(true, called)
    end,
  },
  {
    name = "refresh.refresh_thread_buffer wipes current buffer and reopens same thread",
    run = function()
      local refresh = require("notmuch.refresh")
      local reopened
      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_name(buf, "thread:refreshabc")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "thread body" })

      with_mock_notmuch({
        show_thread = function(thread)
          reopened = thread
        end,
      }, function()
        refresh.refresh_thread_buffer()
      end)

      H.eq(false, vim.api.nvim_buf_is_valid(buf))
      H.eq("thread:refreshabc", reopened)
    end,
  },
  {
    name = "refresh.refresh_hello_buffer wipes current buffer and reopens tag list",
    run = function()
      local refresh = require("notmuch.refresh")
      local called = false
      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_name(buf, "RefreshTags")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Hints:", "inbox" })

      with_mock_notmuch({
        show_all_tags = function()
          called = true
        end,
      }, function()
        refresh.refresh_hello_buffer()
      end)

      H.eq(false, vim.api.nvim_buf_is_valid(buf))
      H.eq(true, called)
    end,
  },
}
