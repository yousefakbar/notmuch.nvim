local s = {}

local config = require("notmuch.config")
local current_sync_job = nil

-- Public job management functions
s.create_job = function(cmd, opts)
  opts = opts or {}
  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = opts.on_stdout,
    on_stderr = opts.on_stderr,
    on_exit = opts.on_exit,
    stdout_buffered = opts.stdout_buffered or false,
    stderr_buffered = opts.stderr_buffered or false,
  })
  return job_id
end

s.stop_job = function(job_id)
  if job_id then
    vim.fn.jobstop(job_id)
    return true
  end
  return false
end

s.is_job_running = function(job_id)
  return job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1
end

s.get_current_sync_job = function()
  return current_sync_job
end

s.set_current_sync_job = function(job_id)
  current_sync_job = job_id
end

-- UI-specific functions
local ui = {}

ui.safe_buf_set_option = function(buf, name, value)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf][name] = value
  end
end

ui.safe_buf_set_lines = function(buf, start, end_, strict, lines)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_set_lines(buf, start, end_, strict, lines)
  end
end

ui.find_sync_buffer = function()
  return vim.fn.bufnr("notmuch-sync")
end

ui.clear_buffer = function(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    ui.safe_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    ui.safe_buf_set_option(buf, "modifiable", false)
  end
end

ui.setup_cancel_keymap = function(buf, job_id, opts)
  opts = opts or {}
  vim.keymap.set("n", "<C-c>", function()
    if s.is_job_running(job_id) and s.stop_job(job_id) then
      if vim.api.nvim_buf_is_valid(buf) then
        ui.safe_buf_set_option(buf, "modifiable", true)
        ui.safe_buf_set_lines(buf, -1, -1, false, { "", opts.cancel_msg or "Job cancelled!" })
        ui.safe_buf_set_option(buf, "modifiable", false)
      end
    elseif not s.is_job_running(job_id) then
      vim.notify("Sync job already exited", vim.log.levels.WARN)
    end
  end, { buffer = buf, desc = opts.desc or "Cancel job" })
end

ui.switch_to_buffer = function(buf)
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
    return true
  end
  return false
end

ui.create_sync_buffer = function()
  vim.cmd("botright 10new")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_name(buf, "notmuch-sync")
  return buf
end

s.ui = ui

s.sync_maildir = function()
  -- Check if sync is already running
  if current_sync_job then
    local buf = ui.find_sync_buffer()
    if buf ~= -1 then
      ui.switch_to_buffer(buf)
      vim.notify("Sync is already running. Showing existing sync buffer.", vim.log.levels.WARN)
    else
      vim.notify("Sync is already running.", vim.log.levels.WARN)
    end
    return
  end

  local sync_cmd = config.options.maildir_sync_cmd .. " ; notmuch new"
  local sync_mode = config.options.sync and config.options.sync.sync_mode or "buffer"

  if sync_mode == "background" then
    vim.notify("Syncing and reindexing your Maildir in background...", vim.log.levels.INFO)
    current_sync_job = s.create_job(sync_cmd, {
      on_exit = function(_, code)
        current_sync_job = nil
        if code == 0 then
          vim.notify("Maildir sync finished successfully!", vim.log.levels.INFO)
        else
          vim.notify("Maildir sync failed!", vim.log.levels.ERROR)
        end
      end,
    })
    return
  end

  if sync_mode == "terminal" then
    vim.notify("Syncing and reindexing your Maildir...", vim.log.levels.INFO)

    -- Check for concurrent sync before opening terminal
    if current_sync_job then
      vim.notify("Sync is already running.", vim.log.levels.WARN)
      return
    end

    -- Open terminal split
    vim.cmd("botright 15split | terminal")
    local term_buf = vim.api.nvim_get_current_buf()
    local term_job = vim.b.terminal_job_id
    current_sync_job = term_job

    -- Set up TermClose autocmd BEFORE sending command (race condition protection)
    local aug = vim.api.nvim_create_augroup("NotmuchSync_" .. term_buf, { clear = true })
    vim.api.nvim_create_autocmd("TermClose", {
      group = aug,
      pattern = "*", -- Workaround for Neovim bug with buffer-specific TermClose
      once = true,
      callback = function(ev)
        -- Only process TermClose for our specific terminal buffer
        if ev.buf ~= term_buf then
          return
        end

        current_sync_job = nil
        local exit_code = vim.v.event.status or -1

        -- Defer notification on success to avoid buffer close redraw issues
        if exit_code == 0 then
          vim.defer_fn(function()
            vim.notify("✅ Maildir sync finished successfully!", vim.log.levels.INFO)
          end, 500)
        else
          vim.notify(
            "❌ Maildir sync failed (exit code: " .. exit_code .. ")",
            vim.log.levels.ERROR
          )
        end
      end,
    })

    -- Send command to terminal and exit shell after completion
    vim.fn.chansend(term_job, sync_cmd .. " ; exit\n")

    -- Start in insert mode for immediate interaction (e.g., passphrase prompt)
    vim.cmd("startinsert")

    return
  end

  vim.notify("Syncing and reindexing your Maildir...", vim.log.levels.INFO)

  local buf = ui.find_sync_buffer()
  if buf ~= -1 then
    ui.switch_to_buffer(buf)
    ui.clear_buffer(buf)
  else
    buf = ui.create_sync_buffer()
  end

  -- Set initial buffer text with user friendly instructions
  ui.safe_buf_set_option(buf, "modifiable", true)
  ui.safe_buf_set_lines(buf, 0, -1, false, {
    "== Syncing (Press `<C-c>` to cancel) ==",
    "",
    "> " .. sync_cmd,
    "",
  })

  local output = {}

  local job_id = s.create_job(sync_cmd, {
    on_stdout = function(_, data)
      if data then
        if data[#data] == "" then
          table.remove(data, #data)
        end
        for _, line in ipairs(data) do
          table.insert(output, line)
        end
        ui.safe_buf_set_option(buf, "modifiable", true)
        ui.safe_buf_set_lines(buf, -1, -1, false, data)
        ui.safe_buf_set_option(buf, "modifiable", false)
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        ui.safe_buf_set_option(buf, "modifiable", true)
        ui.safe_buf_set_lines(buf, -1, -1, false, data)
        ui.safe_buf_set_option(buf, "modifiable", false)
      end
    end,
    on_exit = function(_, code)
      current_sync_job = nil
      ui.safe_buf_set_option(buf, "modifiable", true)
      if code == 0 then
        ui.safe_buf_set_lines(buf, -1, -1, false, { "", "Maildir sync finished successfully!" })
        vim.notify("Maildir sync finished successfully!", vim.log.levels.INFO)
      else
        ui.safe_buf_set_lines(buf, -1, -1, false, { "", "Maildir sync failed!" })
        vim.notify("Maildir sync failed!", vim.log.levels.ERROR)
      end
      ui.safe_buf_set_option(buf, "modifiable", false)
    end,
    stdout_buffered = false,
    stderr_buffered = false,
  })
  current_sync_job = job_id

  ui.setup_cancel_keymap(buf, job_id, { cancel_msg = "Sync job cancelled!" })
end

return s

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
