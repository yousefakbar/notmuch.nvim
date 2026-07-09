local H = dofile("tests/helpers.lua")

local function map_callback(mode, lhs, buf)
  local target = lhs:lower()
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhs:lower() == target then return m.callback end
  end
end

local function wait_for_thread_lines()
  H.wait_until(function()
    return table.concat(H.current_lines(), "\n"):find("thread:", 1, true)
  end, 3000)
end

local function current_thread_id()
  local line = vim.api.nvim_get_current_line()
  local id = line:match("^thread:([0-9A-Za-z]+)")
  H.ok(id, "expected current line to contain a thread id: " .. line)
  return id
end

local function notmuch_count(query)
  return tonumber((H.system({ "notmuch", "count", query }):gsub("%s+", ""))) or 0
end

return {
  {
    name = ":Notmuch opens the tag landing buffer",
    run = function()
      vim.cmd("Notmuch")

      H.eq("Tags", vim.api.nvim_buf_get_name(0):match("([^/]+)$"))
      H.eq("notmuch-hello", vim.bo.filetype)

      local lines = H.current_lines()
      H.contains(lines, "Hints:")
      H.contains(lines, "inbox")
      H.contains(lines, "unread")
    end,
  },
  {
    name = ":NmSearch populates a threads buffer asynchronously",
    run = function()
      vim.cmd("NmSearch tag:inbox")

      H.wait_until(function()
        local lines = H.current_lines()
        return #lines > 1 and table.concat(lines, "\n"):find("thread:", 1, true)
      end, 3000)

      H.eq("notmuch-threads", vim.bo.filetype)
      H.contains(H.current_lines(), "Hints:")
      H.contains(H.current_lines(), "thread:")
    end,
  },
  {
    name = "show_thread renders a thread and sets metadata buffer variables",
    run = function()
      local thread_id = H.first_thread_id("tag:inbox")
      require("notmuch").show_thread("thread:" .. thread_id)

      H.eq("mail", vim.bo.filetype)
      H.ok(vim.b.notmuch_thread, "missing vim.b.notmuch_thread")
      H.ok(vim.b.notmuch_messages, "missing vim.b.notmuch_messages")
      H.eq(thread_id, vim.b.notmuch_thread.id)
      H.ok(vim.b.notmuch_thread.message_count > 0, "expected message_count > 0")
      H.ok(#vim.b.notmuch_messages > 0, "expected message metadata")

      local lines = H.current_lines()
      H.contains(lines, "Hints:")
      H.contains(lines, "Subject:")
      H.contains(lines, "From:")
      H.contains(lines, "}}}")
    end,
  },
  {
    name = "e2e basic read workflow selects inbox and updates cursor status in thread view",
    run = function()
      vim.cmd("Notmuch")
      local inbox_line
      for i, line in ipairs(H.current_lines()) do
        if line == "inbox" then inbox_line = i end
      end
      H.ok(inbox_line, "expected inbox tag on hello page")
      vim.api.nvim_win_set_cursor(0, { inbox_line, 0 })
      local cb = map_callback("n", "<CR>", vim.api.nvim_get_current_buf())
      H.ok(cb, "missing hello <CR> mapping")
      cb()

      wait_for_thread_lines()
      H.eq("notmuch-threads", vim.bo.filetype)
      H.eq("tag:inbox", vim.api.nvim_buf_get_name(0):match("([^/]+)$"))

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      require("notmuch").show_thread()
      H.eq("mail", vim.bo.filetype)
      H.ok(vim.b.notmuch_current, "expected current-message metadata")
      H.ok(vim.b.notmuch_status, "expected status string")
      H.contains(vim.b.notmuch_status, "1/")
    end,
  },
  {
    name = "e2e search workflow refresh preserves thread and reverse sorting changes order",
    run = function()
      vim.cmd("NmSearch tag:inbox")
      wait_for_thread_lines()
      local original = H.current_lines()
      H.ok(#original >= 3, "expected multiple inbox threads")
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      local selected = current_thread_id()

      require("notmuch.refresh").refresh_search_buffer()
      wait_for_thread_lines()
      H.contains(vim.api.nvim_get_current_line(), selected)

      local before = H.current_lines()
      require("notmuch").reverse_sort_threads()
      local after = H.current_lines()
      H.eq(before[1], after[1])
      H.eq(before[#before], after[2])
      H.eq(before[2], after[#after])
    end,
  },
  {
    name = "e2e tag workflow toggles thread tags and message tags then refreshes thread tags",
    run = function()
      local nm = require("notmuch")
      local tag_name = "e2e-" .. tostring(vim.uv.hrtime())
      vim.cmd("NmSearch tag:inbox")
      wait_for_thread_lines()
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local thread_id = current_thread_id()

      vim.cmd("TagToggle " .. tag_name)
      H.ok(notmuch_count("thread:" .. thread_id .. " and tag:" .. tag_name) > 0, "expected toggled thread tag")
      vim.cmd("TagToggle " .. tag_name)
      H.eq(0, notmuch_count("thread:" .. thread_id .. " and tag:" .. tag_name))

      nm.show_thread("thread:" .. thread_id)
      local msg_id = vim.b.notmuch_messages[1].id
      vim.api.nvim_win_set_cursor(0, { vim.b.notmuch_messages[1].start_line, 0 })
      vim.cmd("TagAdd " .. tag_name)
      H.eq(1, notmuch_count("id:" .. msg_id .. " and tag:" .. tag_name))
      vim.cmd("TagRm " .. tag_name)
      H.eq(0, notmuch_count("id:" .. msg_id .. " and tag:" .. tag_name))
      vim.cmd("TagToggle " .. tag_name)
      H.eq(1, notmuch_count("id:" .. msg_id .. " and tag:" .. tag_name))

      require("notmuch.refresh").refresh_thread_buffer()
      H.wait_until(function()
        return table.concat(H.current_lines(), "\n"):find(tag_name, 1, true)
      end, 3000)
      vim.cmd("TagRm " .. tag_name)
    end,
  },
  {
    name = "e2e attachment workflow opens, saves, views, and opens fixture attachments",
    run = function()
      local nm = require("notmuch")
      local attach = require("notmuch.attach.parts")
      local config = require("notmuch.config")
      local old_open, old_view = config.options.open_handler, config.options.view_handler
      local opened, viewed
      config.options.open_handler = function(attachment) opened = attachment.path end
      config.options.view_handler = function(attachment)
        viewed = attachment.path
        return "stub viewed attachment"
      end

      local ok, err = pcall(function()
        vim.cmd("NmSearch tag:attachment")
        wait_for_thread_lines()
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        nm.show_thread()

        local target
        for _, msg in ipairs(vim.b.notmuch_messages) do
          if msg.attachment_count and msg.attachment_count > 0 then
            target = msg
            break
          end
        end
        H.ok(target, "expected a message with attachments")
        vim.api.nvim_win_set_cursor(0, { target.start_line, 0 })

        attach.get_attachments_from_cursor_msg()
        H.eq("notmuch-attach", vim.bo.filetype)
        local parts = vim.b.mime_parts_list
        H.ok(parts and #parts > 0, "expected MIME parts in attachment buffer")

        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        local dir = H.tmpdir()
        local saved = attach.save_attachment_part(dir, false)
        H.ok(saved and saved:find(dir, 1, true), "expected save path in temp dir")
        H.eq(true, vim.uv.fs_stat(saved) ~= nil)

        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        attach.open_attachment_part()
        H.ok(opened and opened:find("/tmp/", 1, true), "expected open handler to receive /tmp path")

        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        attach.view_attachment_part()
        H.ok(viewed and viewed:find("/tmp/", 1, true), "expected view handler to receive /tmp path")
        H.contains(H.current_lines(), "stub viewed attachment")
        vim.cmd("close")
      end)

      config.options.open_handler, config.options.view_handler = old_open, old_view
      if not ok then error(err, 0) end
    end,
  },
  {
    name = "e2e compose workflow adds/removes attachment, builds MIME, and stubs msmtp",
    run = function()
      local send = require("notmuch.send")
      local config = require("notmuch.config")
      local old_confirm = vim.api.nvim_call_function
      local old_chansend = vim.fn.chansend
      local old_from, old_keymaps = config.options.from, config.options.keymaps
      local old_drafts = vim.deepcopy(config.options.drafts)
      local sent_cmd
      config.options.from = "E2E Sender <sender@example.com>"
      config.options.keymaps = { sendmail = "<C-g><C-g>", attachment_window = "<C-g><C-a>" }
      config.options.drafts = { folder = H.tmpdir() .. "/drafts", delete_sent = false, show_sent_drafts = false }
      vim.api.nvim_call_function = function() return 1 end
      vim.fn.chansend = function(job, data)
        sent_cmd = data
        return old_chansend(job, "exit 0\n")
      end

      local ok, err = pcall(function()
        local attachment = H.write_file(H.tmpdir() .. "/compose-attachment.txt", "compose attachment\n")
        send.compose("compose@example.com")
        local main_buf = vim.api.nvim_get_current_buf()
        H.matches(vim.api.nvim_buf_get_name(main_buf), "/drafts/compose/compose%-.*%.eml$")
        vim.api.nvim_buf_set_lines(main_buf, 5, -1, false, { "Compose E2E body" })

        map_callback("n", config.options.keymaps.attachment_window, main_buf)()
        local attach_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(attach_buf, 0, -1, false, { attachment })
        H.same({ attachment }, vim.api.nvim_buf_get_lines(attach_buf, 0, -1, false))
        vim.api.nvim_buf_set_lines(attach_buf, 0, -1, false, {})
        H.eq(true, require("notmuch.util").empty_attachment_window(attach_buf))
        vim.api.nvim_buf_set_lines(attach_buf, 0, -1, false, { attachment })

        vim.api.nvim_set_current_buf(main_buf)
        map_callback("n", config.options.keymaps.sendmail, main_buf)()
        H.wait_until(function() return sent_cmd ~= nil end, 1500)
        H.contains(sent_cmd, "msmtp -t --read-envelope-from")
        H.contains(sent_cmd, " ; exit")
        local send_file = sent_cmd:match("<([^ ;]+)")
        send_file = send_file and (send_file:match("^'(.+)'$") or send_file)
        local text = table.concat(vim.fn.readfile(send_file), "\n")
        H.contains(text, "Content-Type: multipart/mixed")
        H.contains(text, "Content-Disposition: attachment; filename=\"compose-attachment.txt\"")
        H.contains(text, "Compose E2E body")
      end)

      vim.api.nvim_call_function = old_confirm
      vim.fn.chansend = old_chansend
      config.options.from, config.options.keymaps = old_from, old_keymaps
      config.options.drafts = old_drafts
      if not ok then error(err, 0) end
    end,
  },
  {
    name = "e2e reply workflow generates draft, attaches file, and stubs msmtp",
    run = function()
      local nm = require("notmuch")
      local send = require("notmuch.send")
      local config = require("notmuch.config")
      local old_confirm = vim.api.nvim_call_function
      local old_chansend = vim.fn.chansend
      local old_drafts = vim.deepcopy(config.options.drafts)
      local old_keymaps = config.options.keymaps
      local sent_cmd
      config.options.drafts = { folder = H.tmpdir() .. "/drafts", delete_sent = false, show_sent_drafts = false }
      config.options.keymaps = { sendmail = "<C-g><C-g>", attachment_window = "<C-g><C-a>" }
      vim.api.nvim_call_function = function() return 1 end
      vim.fn.chansend = function(job, data)
        sent_cmd = data
        return old_chansend(job, "exit 0\n")
      end

      local ok, err = pcall(function()
        local thread_id = H.first_thread_id("tag:inbox")
        nm.show_thread("thread:" .. thread_id)
        local msg = vim.b.notmuch_messages[1]
        vim.api.nvim_win_set_cursor(0, { msg.start_line, 0 })
        send.reply()
        local reply_buf = vim.api.nvim_get_current_buf()
        H.matches(vim.api.nvim_buf_get_name(reply_buf), "/drafts/replies/.*/reply%-.*%.eml$")
        H.contains(H.current_lines(), "Subject:")

        local attachment = H.write_file(H.tmpdir() .. "/reply-attachment.txt", "reply attachment\n")
        map_callback("n", config.options.keymaps.attachment_window, reply_buf)()
        local attach_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(attach_buf, 0, -1, false, { attachment })
        vim.api.nvim_set_current_buf(reply_buf)
        map_callback("n", config.options.keymaps.sendmail, reply_buf)()
        H.wait_until(function() return sent_cmd ~= nil end, 1500)
        H.contains(sent_cmd, "msmtp -t --read-envelope-from")
        local send_file = sent_cmd:match("<([^ ;]+)")
        send_file = send_file and (send_file:match("^'(.+)'$") or send_file)
        local text = table.concat(vim.fn.readfile(send_file), "\n")
        H.contains(text, "Content-Type: multipart/mixed")
        H.contains(text, "Content-Disposition: attachment; filename=\"reply-attachment.txt\"")
      end)

      vim.api.nvim_call_function = old_confirm
      vim.fn.chansend = old_chansend
      config.options.drafts = old_drafts
      config.options.keymaps = old_keymaps
      if not ok then error(err, 0) end
    end,
  },
  {
    name = "e2e sync workflow covers buffer, background, terminal, and concurrency modes",
    run = function()
      local sync = require("notmuch.sync")
      local config = require("notmuch.config")
      local old_sync_cmd, old_sync_config = config.options.maildir_sync_cmd, config.options.sync
      local old_chansend = vim.fn.chansend
      local old_notify = vim.notify
      local notes, sent_cmd = {}, nil
      vim.notify = function(msg, level) table.insert(notes, { msg = msg, level = level }) end
      vim.fn.chansend = function(job, data)
        sent_cmd = data
        return old_chansend(job, "exit 0\n")
      end

      local ok, err = pcall(function()
        sync.set_current_sync_job(nil)
        config.options.maildir_sync_cmd = "printf sync-ok"
        config.options.sync = { sync_mode = "buffer" }
        sync.sync_maildir()
        H.wait_until(function()
          return table.concat(H.current_lines(), "\n"):find("Maildir sync finished successfully!", 1, true)
        end, 3000)

        config.options.maildir_sync_cmd = "false &&"
        config.options.sync = { sync_mode = "buffer" }
        sync.set_current_sync_job(nil)
        sync.sync_maildir()
        H.wait_until(function()
          return table.concat(H.current_lines(), "\n"):find("Maildir sync failed!", 1, true)
        end, 3000)

        config.options.maildir_sync_cmd = "true"
        config.options.sync = { sync_mode = "background" }
        sync.set_current_sync_job(nil)
        sync.sync_maildir()
        H.wait_until(function()
          return notes[#notes] and notes[#notes].msg:find("finished successfully", 1, true)
        end, 3000)

        config.options.maildir_sync_cmd = "printf terminal-sync"
        config.options.sync = { sync_mode = "terminal" }
        sync.set_current_sync_job(nil)
        sync.sync_maildir()
        H.eq("printf terminal-sync ; notmuch new ; exit\n", sent_cmd)

        local old_create_job = sync.create_job
        local old_is_running = sync.is_job_running
        local created = false
        sync.set_current_sync_job(999999)
        sync.is_job_running = function() return true end
        sync.create_job = function() created = true end
        config.options.sync = { sync_mode = "background" }
        sync.sync_maildir()
        H.eq(false, created)
        H.contains(notes[#notes].msg, "already running")
        sync.create_job = old_create_job
        sync.is_job_running = old_is_running
        sync.set_current_sync_job(nil)
      end)

      config.options.maildir_sync_cmd, config.options.sync = old_sync_cmd, old_sync_config
      vim.fn.chansend = old_chansend
      vim.notify = old_notify
      sync.set_current_sync_job(nil)
      if not ok then error(err, 0) end
    end,
  },
}
