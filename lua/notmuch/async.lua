local a = {}

-- Runs `notmuch search` asynchronously
--
-- This function leverages the `vim.uv` library to spawn a subprocess and
-- asynchronously run the `notmuch` search query in the background so it does
-- not block `nvim`s event loop and allow seamless UX while results flow in
--
---@param search string Search terms to pass to `notmuch search`; see `notmuch-search-terms(7)`.
---@param buf integer Buffer id to stream search results into.
---@param on_complete fun() Callback invoked after the `notmuch search` process exits.
--
---@usage
-- -- Refer to `init.lua` for example invocation
-- require('notmuch.async').run_notmuch_search('tag:inbox', 0, function()
--   print('Notmuch search process completed.')
-- end)
a.run_notmuch_search = function(search, buf, on_complete)
  -- Set up pipes for stdout and stderr to capture command output
  local stdout = vim.uv.new_pipe(false)
  local stderr = vim.uv.new_pipe(false)

  -- Spawn subprocess using vim.uv
  local handle
  handle = vim.uv.spawn(
    "notmuch",
    {
      args = { "search", search },
      stdio = { nil, stdout, stderr },
    },
    vim.schedule_wrap(function()
      -- Close the pipes and handle
      stdout:close()
      stderr:close()
      handle:close()

      -- Call the completion callback
      on_complete()
    end)
  )

  -- Helper variable for maintaining incomplete lines between reads
  local partial_data = ""

  -- Read data from stdout and write it to the buffer
  vim.uv.read_start(
    stdout,
    vim.schedule_wrap(function(_, data)
      if data then
        -- Combine earlier incomplete chunk with newest read
        partial_data = partial_data .. data
        local lines = vim.split(partial_data, "\n")
        -- collect incomplete line at the tail of lines
        partial_data = table.remove(lines)

        -- Check if buffer is still valid before writing
        -- This prevents errors when buffer is deleted (e.g., during refresh)
        if not vim.api.nvim_buf_is_valid(buf) then
          handle:kill()
          return
        end

        -- Paste lines into the tail of `buf`
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
        vim.bo[buf].modifiable = false
      end
    end)
  )

  -- Log errors from stderr
  vim.uv.read_start(
    stderr,
    vim.schedule_wrap(function(err, data)
      if err then
        vim.notify("ERROR: " .. err)
      elseif data then
        vim.notify("ERROR: " .. data)
      end
    end)
  )
end

return a
