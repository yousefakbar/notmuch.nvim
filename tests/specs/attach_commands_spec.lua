local H = dofile("tests/helpers.lua")

return {
  {
    name = "attach.commands.Attach adds absolute validated attachments and rejects duplicates",
    run = function()
      local commands = require("notmuch.attach.commands")
      local dir = H.tmpdir()
      local file = H.write_file(dir .. "/doc.txt", "hello")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_var(buf, "notmuch_attachments", {})

      local old_notify = vim.notify
      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local handler = commands.attach_handler(buf)
      handler({ args = file })
      handler({ args = file })

      local attachments = vim.api.nvim_buf_get_var(buf, "notmuch_attachments")
      H.same({ vim.fn.fnamemodify(file, ":p") }, attachments)
      H.contains(notifications[1].msg, "Attached:")
      H.contains(notifications[2].msg, "Already attached:")
      H.eq(vim.log.levels.WARN, notifications[2].level)

      vim.notify = old_notify
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.commands.Attach rejects missing and unreadable/special files",
    run = function()
      local commands = require("notmuch.attach.commands")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_var(buf, "notmuch_attachments", {})

      local old_notify = vim.notify
      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      commands.attach_handler(buf)({ args = "/definitely/missing/notmuch.nvim" })
      commands.attach_handler(buf)({ args = "/dev/null" })

      H.same({}, vim.api.nvim_buf_get_var(buf, "notmuch_attachments"))
      H.contains(notifications[1].msg, "Cannot attach")
      H.eq(vim.log.levels.ERROR, notifications[1].level)
      H.contains(notifications[2].msg, "Cannot attach")
      H.contains(notifications[2].msg, "not a regular file")
      H.eq(vim.log.levels.ERROR, notifications[2].level)

      vim.notify = old_notify
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.commands.AttachRemove removes expanded absolute paths",
    run = function()
      local commands = require("notmuch.attach.commands")
      local cwd = vim.fn.getcwd()
      local dir = cwd .. "/tests/tmp/attach-cmd"
      vim.fn.mkdir(dir, "p")
      local file = H.write_file(dir .. "/remove-me.txt", "hello")
      vim.cmd("lcd " .. vim.fn.fnameescape(dir))

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_var(buf, "notmuch_attachments", { vim.fn.fnamemodify(file, ":p") })

      local old_notify = vim.notify
      local notification
      vim.notify = function(msg, level)
        notification = { msg = msg, level = level }
      end

      commands.remove_handler(buf)({ args = "remove-me.txt" })

      H.same({}, vim.api.nvim_buf_get_var(buf, "notmuch_attachments"))
      H.contains(notification.msg, "Removed:")
      H.eq(vim.log.levels.INFO, notification.level)

      vim.notify = old_notify
      vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.commands.Attach rejects directories and removal errors for missing attachments",
    run = function()
      local commands = require("notmuch.attach.commands")
      local dir = H.tmpdir()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_var(buf, "notmuch_attachments", {})
      local old_notify = vim.notify
      local notes = {}
      vim.notify = function(msg, level)
        table.insert(notes, { msg = msg, level = level })
      end

      commands.attach_handler(buf)({ args = dir })
      commands.remove_handler(buf)({ args = dir .. "/missing.txt" })

      H.same({}, vim.api.nvim_buf_get_var(buf, "notmuch_attachments"))
      H.contains(notes[1].msg, "Cannot attach")
      H.eq(vim.log.levels.ERROR, notes[1].level)
      H.contains(notes[2].msg, "File not in attachments")
      H.eq(vim.log.levels.ERROR, notes[2].level)

      vim.notify = old_notify
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.commands.AttachList prints empty and populated attachment lists",
    run = function()
      local commands = require("notmuch.attach.commands")
      local dir = H.tmpdir()
      local file = H.write_file(dir .. "/listed.txt", string.rep("x", 2048))
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_var(buf, "notmuch_attachments", {})
      local old_print = print
      local printed = {}
      print = function(msg)
        table.insert(printed, tostring(msg))
      end

      commands.list_handler(buf)()
      H.contains(printed, "No attachments")
      vim.api.nvim_buf_set_var(buf, "notmuch_attachments", { file, dir .. "/missing.txt" })
      commands.list_handler(buf)()
      H.contains(printed, "Attachments (2):")
      H.contains(printed, "[1] " .. file .. " (2 KB)")
      H.contains(printed, "[2] " .. dir .. "/missing.txt (0 KB)")

      print = old_print
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.commands.AttachRemove completion returns current attachments",
    run = function()
      local commands = require("notmuch.attach.commands")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_var(buf, "notmuch_attachments", { "/a", "/b" })
      H.same({ "/a", "/b" }, commands.remove_completion(buf)())
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.commands.setup_buffer registers AttachOpen command",
    run = function()
      local commands = require("notmuch.attach.commands")
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_var(buf, "notmuch_attachments", {})

      H.eq(true, commands.setup_buffer(buf))
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("AttachOpen")
      end)

      local scratch_buf = vim.api.nvim_buf_get_var(buf, "notmuch_attachment_scratch_buf")
      H.ok(vim.api.nvim_buf_is_valid(scratch_buf), "AttachOpen should create a scratch buffer")
      H.eq(buf, vim.api.nvim_buf_get_var(scratch_buf, "notmuch_parent_draft_buf"))
      pcall(vim.cmd, "silent! %bwipeout!")
    end,
  },
}
