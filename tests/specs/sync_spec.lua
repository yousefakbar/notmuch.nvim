local H = dofile("tests/helpers.lua")

local function map_callback(mode, lhs, buf)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhs == lhs then
      return m.callback
    end
  end
end

return {
  {
    name = "sync job helpers forward callbacks, stop jobs, and report running status",
    run = function()
      local sync = require("notmuch.sync")
      local old_jobstart, old_jobstop, old_jobwait = vim.fn.jobstart, vim.fn.jobstop, vim.fn.jobwait
      local started, stopped
      vim.fn.jobstart = function(cmd, opts)
        started = { cmd = cmd, opts = opts }
        return 42
      end
      vim.fn.jobstop = function(job_id)
        stopped = job_id
      end
      vim.fn.jobwait = function(jobs, timeout)
        H.same({ 42 }, jobs)
        H.eq(0, timeout)
        return { -1 }
      end

      local cb = function() end
      H.eq(42, sync.create_job("echo ok", { on_stdout = cb, stdout_buffered = true }))
      H.eq("echo ok", started.cmd)
      H.eq(cb, started.opts.on_stdout)
      H.eq(true, started.opts.stdout_buffered)
      H.eq(false, started.opts.stderr_buffered)
      H.eq(true, sync.stop_job(42))
      H.eq(42, stopped)
      H.eq(false, sync.stop_job(nil))
      H.eq(true, sync.is_job_running(42))
      H.eq(nil, sync.is_job_running(nil))
      sync.set_current_sync_job(77)
      H.eq(77, sync.get_current_sync_job())
      sync.set_current_sync_job(nil)

      vim.fn.jobstart, vim.fn.jobstop, vim.fn.jobwait = old_jobstart, old_jobstop, old_jobwait
    end,
  },
  {
    name = "sync buffer mode creates reusable nofile buffer and appends output/status",
    run = function()
      local sync = require("notmuch.sync")
      local config = require("notmuch.config")
      config.options.maildir_sync_cmd = "printf sync"
      config.options.sync = { sync_mode = "buffer" }
      sync.set_current_sync_job(nil)

      local old_create_job = sync.create_job
      local old_notify = vim.notify
      local notes = {}
      vim.notify = function(msg, level)
        table.insert(notes, { msg = msg, level = level })
      end
      sync.create_job = function(cmd, opts)
        H.eq("printf sync ; notmuch new", cmd)
        opts.on_stdout(1, { "line one", "" })
        opts.on_stderr(1, { "warning" })
        opts.on_exit(1, 0)
        return 123
      end

      sync.sync_maildir()
      local buf = vim.api.nvim_get_current_buf()
      H.eq("notmuch-sync", vim.api.nvim_buf_get_name(buf):match("([^/]+)$"))
      H.eq("nofile", vim.bo[buf].buftype)
      H.eq("wipe", vim.bo[buf].bufhidden)
      H.eq(false, vim.bo[buf].swapfile)
      H.eq(false, vim.bo[buf].modifiable)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      H.contains(lines, "== Syncing")
      H.contains(lines, "line one")
      H.contains(lines, "warning")
      H.contains(lines, "Maildir sync finished successfully!")
      H.ok(#notes >= 2, "expected start and success notifications")

      sync.create_job = old_create_job
      vim.notify = old_notify
      sync.set_current_sync_job(nil)
    end,
  },
  {
    name = "sync background mode avoids buffers and clears current job on exit",
    run = function()
      local sync = require("notmuch.sync")
      local config = require("notmuch.config")
      config.options.maildir_sync_cmd = "true"
      config.options.sync = { sync_mode = "background" }
      sync.set_current_sync_job(nil)
      local before = vim.api.nvim_get_current_buf()

      local old_create_job = sync.create_job
      local old_notify = vim.notify
      local notes = {}
      vim.notify = function(msg, level)
        table.insert(notes, { msg = msg, level = level })
      end
      local exit_cb
      sync.create_job = function(_, opts)
        exit_cb = opts.on_exit
        return 321
      end

      sync.sync_maildir()
      H.eq(before, vim.api.nvim_get_current_buf())
      H.eq(321, sync.get_current_sync_job())
      exit_cb(321, 0)
      H.eq(nil, sync.get_current_sync_job())
      H.contains(notes[#notes].msg, "successfully")

      sync.create_job = old_create_job
      vim.notify = old_notify
    end,
  },
  {
    name = "sync buffer mode reports failure and notifies error",
    run = function()
      local sync = require("notmuch.sync")
      local config = require("notmuch.config")
      config.options.maildir_sync_cmd = "false"
      config.options.sync = { sync_mode = "buffer" }
      sync.set_current_sync_job(nil)

      local old_create_job = sync.create_job
      local old_notify = vim.notify
      local notes = {}
      vim.notify = function(msg, level)
        table.insert(notes, { msg = msg, level = level })
      end
      sync.create_job = function(_, opts)
        opts.on_stderr(1, { "boom" })
        opts.on_exit(1, 2)
        return 222
      end

      sync.sync_maildir()
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      H.contains(lines, "boom")
      H.contains(lines, "Maildir sync failed!")
      H.eq(vim.log.levels.ERROR, notes[#notes].level)
      H.contains(notes[#notes].msg, "failed")

      sync.create_job = old_create_job
      vim.notify = old_notify
      sync.set_current_sync_job(nil)
    end,
  },
  {
    name = "sync buffer mode Ctrl-C cancels running jobs and warns after exit",
    run = function()
      local sync = require("notmuch.sync")
      local config = require("notmuch.config")
      config.options.maildir_sync_cmd = "sleep 10"
      config.options.sync = { sync_mode = "buffer" }
      sync.set_current_sync_job(nil)

      local old_create_job = sync.create_job
      local old_stop_job = sync.stop_job
      local old_is_running = sync.is_job_running
      local old_notify = vim.notify
      local stopped
      local running = true
      local note
      sync.create_job = function()
        return 333
      end
      sync.stop_job = function(job_id)
        stopped = job_id
        running = false
        return true
      end
      sync.is_job_running = function(job_id)
        return job_id == 333 and running
      end
      vim.notify = function(msg, level)
        note = { msg = msg, level = level }
      end

      sync.sync_maildir()
      local buf = vim.api.nvim_get_current_buf()
      local cb = map_callback("n", "<C-C>", buf)
      H.ok(cb, "missing cancel keymap")
      cb()
      H.eq(333, stopped)
      H.contains(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "Sync job cancelled!")
      H.eq(false, vim.bo[buf].modifiable)

      cb()
      H.contains(note.msg, "already exited")
      H.eq(vim.log.levels.WARN, note.level)

      sync.create_job = old_create_job
      sync.stop_job = old_stop_job
      sync.is_job_running = old_is_running
      vim.notify = old_notify
      sync.set_current_sync_job(nil)
    end,
  },
  {
    name = "sync background mode notifies failure",
    run = function()
      local sync = require("notmuch.sync")
      local config = require("notmuch.config")
      config.options.maildir_sync_cmd = "false"
      config.options.sync = { sync_mode = "background" }
      sync.set_current_sync_job(nil)

      local old_create_job = sync.create_job
      local old_notify = vim.notify
      local notes = {}
      local exit_cb
      sync.create_job = function(_, opts)
        exit_cb = opts.on_exit
        return 444
      end
      vim.notify = function(msg, level)
        table.insert(notes, { msg = msg, level = level })
      end

      sync.sync_maildir()
      H.eq(444, sync.get_current_sync_job())
      exit_cb(444, 9)
      H.eq(nil, sync.get_current_sync_job())
      H.contains(notes[#notes].msg, "failed")
      H.eq(vim.log.levels.ERROR, notes[#notes].level)

      sync.create_job = old_create_job
      vim.notify = old_notify
      sync.set_current_sync_job(nil)
    end,
  },
  {
    name = "sync terminal mode sends command, starts insert, clears job, and notifies success",
    run = function()
      local sync = require("notmuch.sync")
      local config = require("notmuch.config")
      config.options.maildir_sync_cmd = "printf sync"
      config.options.sync = { sync_mode = "terminal" }
      sync.set_current_sync_job(nil)

      local old_chansend = vim.fn.chansend
      local old_cmd = vim.cmd
      local old_notify = vim.notify
      local sent_cmd, term_job
      local cmds, notes = {}, {}
      vim.cmd = function(cmd)
        table.insert(cmds, cmd)
        return old_cmd(cmd)
      end
      vim.notify = function(msg, level)
        table.insert(notes, { msg = msg, level = level })
      end
      vim.fn.chansend = function(job, data)
        term_job = job
        sent_cmd = data
        return old_chansend(job, "exit 0\n")
      end

      local ok, err = pcall(function()
        sync.sync_maildir()
        H.ok(term_job, "expected terminal job id")
        H.eq(term_job, sync.get_current_sync_job())
        H.eq("printf sync ; notmuch new ; exit\n", sent_cmd)
        H.list_contains(cmds, "botright 15split | terminal")
        H.list_contains(cmds, "startinsert")
        H.wait_until(function()
          return sync.get_current_sync_job() == nil
        end, 1500)
        H.wait_until(function()
          return notes[#notes] and notes[#notes].msg:find("finished successfully", 1, true)
        end, 2000)
        H.eq(vim.log.levels.INFO, notes[#notes].level)
      end)

      vim.fn.chansend = old_chansend
      vim.cmd = old_cmd
      vim.notify = old_notify
      sync.set_current_sync_job(nil)
      if not ok then
        error(err, 0)
      end
    end,
  },
  {
    name = "sync terminal mode notifies failure exit code",
    run = function()
      local sync = require("notmuch.sync")
      local config = require("notmuch.config")
      config.options.maildir_sync_cmd = "false"
      config.options.sync = { sync_mode = "terminal" }
      sync.set_current_sync_job(nil)

      local old_chansend = vim.fn.chansend
      local old_notify = vim.notify
      local sent_cmd
      local notes = {}
      vim.notify = function(msg, level)
        table.insert(notes, { msg = msg, level = level })
      end
      vim.fn.chansend = function(job, data)
        sent_cmd = data
        return old_chansend(job, "exit 7\n")
      end

      local ok, err = pcall(function()
        sync.sync_maildir()
        H.eq("false ; notmuch new ; exit\n", sent_cmd)
        H.wait_until(function()
          return sync.get_current_sync_job() == nil
        end, 1500)
        H.wait_until(function()
          return notes[#notes] and notes[#notes].msg:find("exit code: 7", 1, true)
        end, 1500)
        H.eq(vim.log.levels.ERROR, notes[#notes].level)
      end)

      vim.fn.chansend = old_chansend
      vim.notify = old_notify
      sync.set_current_sync_job(nil)
      if not ok then
        error(err, 0)
      end
    end,
  },
  {
    name = "starting sync while a job is running switches to existing sync buffer when present",
    run = function()
      local sync = require("notmuch.sync")
      local old_is_running = sync.is_job_running
      local old_create_job = sync.create_job
      local old_notify = vim.notify
      sync.set_current_sync_job(999)
      sync.is_job_running = function()
        return true
      end
      sync.create_job = function()
        error("should not create job")
      end
      local note
      vim.notify = function(msg, level)
        note = { msg = msg, level = level }
      end

      local existing = vim.fn.bufnr("notmuch-sync")
      if existing ~= -1 then
        vim.api.nvim_buf_delete(existing, { force = true })
      end
      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_name(buf, "notmuch-sync")
      vim.cmd("vnew")
      H.ok(vim.api.nvim_get_current_buf() ~= buf, "expected to start elsewhere")
      sync.sync_maildir()
      H.eq(buf, vim.api.nvim_get_current_buf())
      H.contains(note.msg, "Showing existing sync buffer")
      H.eq(vim.log.levels.WARN, note.level)

      sync.is_job_running = old_is_running
      sync.create_job = old_create_job
      vim.notify = old_notify
      sync.set_current_sync_job(nil)
    end,
  },
  {
    name = "starting sync while a job is running does not start another job",
    run = function()
      local sync = require("notmuch.sync")
      sync.set_current_sync_job(999)
      local old_is_running = sync.is_job_running
      local old_create_job = sync.create_job
      local old_notify = vim.notify
      local created = false
      local note
      sync.is_job_running = function()
        return true
      end
      sync.create_job = function()
        created = true
      end
      vim.notify = function(msg, level)
        note = { msg = msg, level = level }
      end

      sync.sync_maildir()
      H.eq(false, created)
      H.contains(note.msg, "already running")
      H.eq(vim.log.levels.WARN, note.level)

      sync.is_job_running = old_is_running
      sync.create_job = old_create_job
      vim.notify = old_notify
      sync.set_current_sync_job(nil)
    end,
  },
}
