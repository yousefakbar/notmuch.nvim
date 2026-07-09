local H = dofile("tests/helpers.lua")

local function with_mocked_loop(run)
  local old_new_pipe = vim.uv.new_pipe
  local old_spawn = vim.uv.spawn
  local old_read_start = vim.uv.read_start

  local state = {
    pipes = {},
    reads = {},
    spawned = nil,
    killed = false,
    closed_handle = false,
  }

  vim.uv.new_pipe = function()
    local pipe = {
      closed = false,
      close = function(self) self.closed = true end,
    }
    table.insert(state.pipes, pipe)
    return pipe
  end

  vim.uv.spawn = function(cmd, opts, on_exit)
    state.spawned = { cmd = cmd, opts = opts, on_exit = on_exit }
    local handle = {
      close = function() state.closed_handle = true end,
      kill = function() state.killed = true end,
    }
    state.handle = handle
    return handle
  end

  vim.uv.read_start = function(pipe, cb)
    state.reads[pipe] = cb
  end

  local ok, err = pcall(run, state)

  vim.uv.new_pipe = old_new_pipe
  vim.uv.spawn = old_spawn
  vim.uv.read_start = old_read_start

  if not ok then error(err, 0) end
end

return {
  {
    name = "async search spawns notmuch and appends chunks while toggling modifiable",
    run = function()
      with_mocked_loop(function(state)
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Hints: keep" })
        vim.bo[buf].modifiable = false

        require("notmuch.async").run_notmuch_search("tag:inbox", buf, function() end)

        H.eq("notmuch", state.spawned.cmd)
        H.same({ "search", "tag:inbox" }, state.spawned.opts.args)
        H.eq(state.pipes[1], state.spawned.opts.stdio[2])
        H.eq(state.pipes[2], state.spawned.opts.stdio[3])

        state.reads[state.pipes[1]](nil, "thread:one subject\n")
        vim.wait(20)
        H.same({ "Hints: keep", "thread:one subject" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        H.eq(false, vim.bo[buf].modifiable)

        state.reads[state.pipes[1]](nil, "thread:two subject\n")
        vim.wait(20)
        H.same({ "Hints: keep", "thread:one subject", "thread:two subject" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        H.eq(false, vim.bo[buf].modifiable)
      end)
    end,
  },
  {
    name = "async search joins partial lines across chunks",
    run = function()
      with_mocked_loop(function(state)
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Hints: keep" })

        require("notmuch.async").run_notmuch_search("tag:split", buf, function() end)
        state.reads[state.pipes[1]](nil, "thread:par")
        vim.wait(20)
        H.same({ "Hints: keep" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

        state.reads[state.pipes[1]](nil, "tial subject\nthread:next subject\n")
        vim.wait(20)
        H.same({ "Hints: keep", "thread:partial subject", "thread:next subject" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      end)
    end,
  },
  {
    name = "async search kills process when target buffer is deleted",
    run = function()
      with_mocked_loop(function(state)
        local buf = vim.api.nvim_create_buf(true, true)
        require("notmuch.async").run_notmuch_search("tag:gone", buf, function() end)
        vim.api.nvim_buf_delete(buf, { force = true })

        state.reads[state.pipes[1]](nil, "thread:gone\n")
        vim.wait(20)
        H.eq(true, state.killed)
      end)
    end,
  },
  {
    name = "async search runs completion callback after process exits and closes handles",
    run = function()
      with_mocked_loop(function(state)
        local buf = vim.api.nvim_create_buf(true, true)
        local completed = false
        require("notmuch.async").run_notmuch_search("tag:done", buf, function() completed = true end)

        state.spawned.on_exit(0, 0)
        vim.wait(20)
        H.eq(true, completed)
        H.eq(true, state.pipes[1].closed)
        H.eq(true, state.pipes[2].closed)
        H.eq(true, state.closed_handle)
      end)
    end,
  },
  {
    name = "async search notifies stderr output",
    run = function()
      with_mocked_loop(function(state)
        local old_notify = vim.notify
        local note
        vim.notify = function(msg) note = msg end

        local ok, err = pcall(function()
          local buf = vim.api.nvim_create_buf(true, true)
          require("notmuch.async").run_notmuch_search("tag:error", buf, function() end)
          state.reads[state.pipes[2]](nil, "notmuch error")
          vim.wait(20)
          H.eq("ERROR: notmuch error", note)
        end)

        vim.notify = old_notify
        if not ok then error(err, 0) end
      end)
    end,
  },
}
