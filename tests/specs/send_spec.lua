local H = dofile("tests/helpers.lua")

local function map_callback(mode, lhs, buf)
  local target = lhs:lower()
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhs:lower() == target then
      return m.callback
    end
  end
end

local function file_mode(path)
  local stat = vim.uv.fs_stat(path)
  return stat and bit.band(stat.mode, 511) or nil
end

local function assert_private_file(path)
  if vim.fn.has("win32") == 0 then
    H.eq(384, file_mode(path), "expected private file permissions (0600)")
  end
end

local function with_mime_builder_spy(spy, fn)
  local mime = require("notmuch.mime")
  local old_make_mime_msg = mime.make_mime_msg
  mime.make_mime_msg = function(mime_table)
    spy(mime_table)
    return old_make_mime_msg(mime_table)
  end

  local ok, err = pcall(fn)
  mime.make_mime_msg = old_make_mime_msg
  if not ok then
    error(err, 0)
  end
end

local function with_send_env(fn)
  local send = require("notmuch.send")
  local config = require("notmuch.config")
  local thread = require("notmuch.thread")
  local old_from = config.options.from
  local old_keymaps = config.options.keymaps
  local old_call_function = vim.api.nvim_call_function
  local old_sendmail = send.sendmail
  local old_path = vim.env.PATH
  local old_get_current_message_id = thread.get_current_message_id
  local old_logfile = config.options.logfile
  local old_send = vim.deepcopy(config.options.send)
  local old_drafts = vim.deepcopy(config.options.drafts)
  local old_select = vim.ui.select
  local old_system = vim.system
  local dir = H.tmpdir()
  local state = { dir = dir, sent = {} }

  config.options.from = "Sender Name <sender@example.com>"
  config.options.keymaps = {
    sendmail = "<C-g><C-g>",
    attachment_window = "<C-g><C-a>",
  }
  config.options.drafts = {
    folder = dir .. "/drafts",
    delete_sent = false,
    show_sent_drafts = false,
    auto_open_attachment_window = false,
  }
  config.options.send = {
    send_mode = "terminal",
  }
  vim.ui.select = function(_, _, on_choice)
    on_choice(nil)
  end

  local ok, err = pcall(fn, state, send, config, thread)

  config.options.from = old_from
  config.options.keymaps = old_keymaps
  vim.api.nvim_call_function = old_call_function
  send.sendmail = old_sendmail
  vim.env.PATH = old_path
  thread.get_current_message_id = old_get_current_message_id
  config.options.logfile = old_logfile
  config.options.send = old_send
  config.options.drafts = old_drafts
  vim.ui.select = old_select
  vim.system = old_system
  pcall(vim.cmd, "silent! %bwipeout!")

  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "send.compose creates compose draft with headers, recipient, sender, and attachment window",
    run = function()
      with_send_env(function(_, send, config)
        send.compose("to+tag@example.com")
        local main_buf = vim.api.nvim_get_current_buf()
        H.matches(
          vim.api.nvim_buf_get_name(main_buf),
          "/drafts/compose/compose%-%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ%-%x%x%x%x%x%x%x%x%.eml$",
          "expected persistent compose draft filename"
        )
        H.same({
          "From: Sender Name <sender@example.com>",
          "To: to+tag@example.com",
          "Cc: ",
          "Subject: ",
          "",
          'Message body goes here. Add attachments with "'
            .. config.options.keymaps.attachment_window
            .. '" or `:AttachOpen`. Send with "'
            .. config.options.keymaps.sendmail
            .. '".',
        }, vim.api.nvim_buf_get_lines(main_buf, 0, -1, false))

        local ok_scratch =
          pcall(vim.api.nvim_buf_get_var, main_buf, "notmuch_attachment_scratch_buf")
        H.eq(false, ok_scratch, "scratch buffer should not auto-open by default")
        local commands = vim.api.nvim_buf_get_commands(main_buf, {})
        H.ok(commands.Attach, "missing Attach command")
        H.ok(commands.AttachRemove, "missing AttachRemove command")
        H.ok(commands.AttachList, "missing AttachList command")
        H.ok(commands.AttachOpen, "missing AttachOpen command")

        local before_wins = #vim.api.nvim_list_wins()
        local attach_cb = map_callback("n", config.options.keymaps.attachment_window, main_buf)
        H.ok(attach_cb, "missing compose attachment-window keymap")
        attach_cb()
        H.ok(#vim.api.nvim_list_wins() > before_wins, "expected attachment split to open")
        H.ok(
          vim.api.nvim_get_current_buf() ~= main_buf,
          "expected attachment buffer to become current"
        )
        vim.cmd("close")
      end)
    end,
  },
  {
    name = "send.compose auto-opens attachment window when configured",
    run = function()
      with_send_env(function(_, send, config)
        config.options.drafts.auto_open_attachment_window = true

        send.compose("auto@example.com")
        local main_buf = vim.api.nvim_get_current_buf()
        local scratch_buf = vim.api.nvim_buf_get_var(main_buf, "notmuch_attachment_scratch_buf")

        H.ok(vim.api.nvim_buf_is_valid(scratch_buf), "expected linked scratch buffer")
        H.eq(main_buf, vim.api.nvim_buf_get_var(scratch_buf, "notmuch_parent_draft_buf"))
        H.eq("notmuch-attach-draft", vim.bo[scratch_buf].filetype)
        H.eq(
          main_buf,
          vim.api.nvim_get_current_buf(),
          "draft buffer should keep focus after auto-opening scratch"
        )
      end)
    end,
  },
  {
    name = "send.compose send keymap prompts and No confirmation does not send",
    run = function()
      with_send_env(function(state, send, config)
        local prompted = false
        send.sendmail = function(path)
          table.insert(state.sent, path)
          return true
        end
        vim.api.nvim_call_function = function(name, args)
          H.eq("confirm", name)
          H.eq("Send email?", args[1])
          prompted = true
          return 2
        end

        send.compose()
        local main_buf = vim.api.nvim_get_current_buf()
        local send_cb = map_callback("n", config.options.keymaps.sendmail, main_buf)
        H.ok(send_cb, "missing compose send keymap")
        send_cb()

        H.eq(true, prompted)
        H.eq(0, #state.sent)
        H.contains(vim.api.nvim_buf_get_lines(main_buf, 0, -1, false), "Message body goes here")
      end)
    end,
  },
  {
    name = "send.compose Confirm Yes without attachments builds plain message and sends",
    run = function()
      with_send_env(function(state, send, config)
        send.sendmail = function(path)
          table.insert(state.sent, path)
          return true
        end
        vim.api.nvim_call_function = function()
          return 1
        end

        send.compose("plain@example.com")
        local main_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(main_buf, 5, -1, false, { "Hello plain body" })
        map_callback("n", config.options.keymaps.sendmail, main_buf)()

        H.eq(1, #state.sent)
        H.matches(state.sent[1], "%-notmuch%-send%-%w%w%w%w%w%w$")
        assert_private_file(state.sent[1])
        local sent_lines = vim.fn.readfile(state.sent[1])
        H.contains(sent_lines, "From: Sender Name <sender@example.com>")
        H.contains(sent_lines, "To: plain@example.com")
        H.contains(sent_lines, "MIME-Version: 1.0")
        H.contains(sent_lines, "Content-Type: text/plain; charset=utf-8")
        H.contains(sent_lines, "Content-Transfer-Encoding: 8bit")
        H.contains(sent_lines, "Hello plain body")
        H.ok(
          not table.concat(sent_lines, "\n"):find("multipart/mixed", 1, true),
          "plain message should not be multipart"
        )
        local draft_lines = vim.api.nvim_buf_get_lines(main_buf, 0, -1, false)
        H.ok(
          not table.concat(draft_lines, "\n"):find("MIME-Version", 1, true),
          "persistent draft should not be mutated into send artifact"
        )
      end)
    end,
  },
  {
    name = "send.compose Confirm Yes with attachments builds MIME message and sends",
    run = function()
      with_send_env(function(state, send, config)
        local attachment = H.write_file(state.dir .. "/attachment.txt", "attached text\n")
        local body_filename
        local body_mode
        send.sendmail = function(path)
          table.insert(state.sent, path)
          return true
        end
        vim.api.nvim_call_function = function()
          return 1
        end

        with_mime_builder_spy(function(mime_table)
          if mime_table.mime then
            body_filename = mime_table.mime[1].file
            body_mode = file_mode(body_filename)
          end
        end, function()
          send.compose("mime@example.com")
          local main_buf = vim.api.nvim_get_current_buf()
          vim.api.nvim_buf_set_lines(main_buf, 5, -1, false, { "Hello MIME body" })

          map_callback("n", config.options.keymaps.attachment_window, main_buf)()
          local attach_buf = vim.api.nvim_get_current_buf()
          vim.api.nvim_buf_set_lines(attach_buf, 0, -1, false, { attachment })
          vim.api.nvim_set_current_buf(main_buf)

          map_callback("n", config.options.keymaps.sendmail, main_buf)()

          H.eq(1, #state.sent)
          H.matches(state.sent[1], "%-notmuch%-send%-%w%w%w%w%w%w$")
          assert_private_file(state.sent[1])
          local text = table.concat(vim.fn.readfile(state.sent[1]), "\n")
          H.contains(text, "From: Sender Name <sender@example.com>")
          H.contains(text, "To: mime@example.com")
          H.contains(text, "Content-Type: multipart/mixed")
          H.contains(text, 'Content-Disposition: attachment; filename="attachment.txt"')
          H.contains(text, "Hello MIME body")
          local metadata =
            require("notmuch.draft").read_metadata(vim.b[main_buf].notmuch_draft_json_path)
          H.same({ attachment }, metadata.attachments)
        end)

        H.ok(body_filename, "expected MIME body temporary file")
        if vim.fn.has("win32") == 0 then
          H.eq(384, body_mode, "expected private MIME body permissions (0600)")
        end
        H.eq(nil, vim.uv.fs_stat(body_filename), "MIME body temporary file was not deleted")
      end)
    end,
  },
  {
    name = "send.reply gets message id, creates sanitized draft, initializes commands, and reads new drafts",
    run = function()
      with_send_env(function(state, send, config, thread)
        vim.system = function(args)
          H.same({ "notmuch", "reply", "id:msg/with/slash" }, args)
          return {
            wait = function()
              return {
                code = 0,
                stdout = table.concat({
                  "From: Sender Name <sender@example.com>",
                  "To: Reply Target <target@example.com>",
                  "Subject: Re: Fixture",
                  "",
                  "quoted reply body",
                }, "\n"),
                stderr = "",
              }
            end,
          }
        end

        local requested_id
        thread.get_current_message_id = function()
          requested_id = "msg/with/slash"
          return requested_id
        end

        send.reply()
        local buf = vim.api.nvim_get_current_buf()
        H.eq("msg/with/slash", requested_id)
        H.matches(
          vim.api.nvim_buf_get_name(buf),
          "/drafts/replies/"
            .. vim.fn.sha256("msg/with/slash")
            .. "/reply%-%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ%-%x%x%x%x%x%x%x%x%.eml$"
        )
        H.same({}, vim.b[buf].notmuch_attachments)
        H.ok(vim.b[buf].notmuch_draft_json_path, "missing draft sidecar buffer variable")
        H.contains(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "quoted reply body")
        H.ok(map_callback("n", config.options.keymaps.sendmail, buf), "missing reply send keymap")
      end)
    end,
  },
  {
    name = "send.reply reuses existing drafts without duplicating notmuch reply output",
    run = function()
      with_send_env(function(state, send, _, thread)
        vim.system = function()
          error("notmuch reply should not be called when an existing reply draft is selected")
        end

        local draft =
          require("notmuch.draft").create_reply_draft("existing/id", { "Existing draft" })
        thread.get_current_message_id = function()
          return "existing/id"
        end
        vim.ui.select = function(items, opts, on_choice)
          H.eq("Select reply draft:", opts.prompt)
          H.eq("new_reply", items[1].action)
          H.eq("open_reply", items[2].action)
          on_choice(items[2])
        end

        send.reply()
        H.eq(vim.uv.fs_realpath(draft.eml_path), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        H.same({ "Existing draft" }, lines)
      end)
    end,
  },
  {
    name = "send.reply send keymap builds plain or MIME messages and calls sendmail",
    run = function()
      with_send_env(function(state, send, config, thread)
        send.sendmail = function(path)
          table.insert(state.sent, path)
          return true
        end
        vim.api.nvim_call_function = function()
          return 1
        end

        vim.system = function(args)
          local id = args[3]:sub(4)
          return {
            wait = function()
              return {
                code = 0,
                stdout = "From: Sender Name <sender@example.com>\nTo: Recipient <recipient@example.com>\nSubject: Re: "
                  .. id
                  .. "\n\nBody",
                stderr = "",
              }
            end,
          }
        end

        thread.get_current_message_id = function()
          return "plain-reply"
        end
        send.reply()
        local plain_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(plain_buf, 0, -1, false, {
          "From: Sender Name <sender@example.com>",
          "To: Recipient <recipient@example.com>",
          "Subject: Re: Plain",
          "",
          "Plain reply body",
        })
        map_callback("n", config.options.keymaps.sendmail, plain_buf)()
        H.matches(state.sent[#state.sent], "%-notmuch%-send%-%w%w%w%w%w%w$")
        assert_private_file(state.sent[#state.sent])
        H.contains(vim.fn.readfile(state.sent[#state.sent]), "MIME-Version: 1.0")

        thread.get_current_message_id = function()
          return "mime-reply"
        end
        send.reply()
        local mime_buf = vim.api.nvim_get_current_buf()
        local attachment = H.write_file(state.dir .. "/reply-attachment.txt", "reply attachment\n")
        vim.api.nvim_buf_set_lines(mime_buf, 0, -1, false, {
          "From: Sender Name <sender@example.com>",
          "To: Recipient <recipient@example.com>",
          "Subject: Re: MIME",
          "",
          "MIME reply body",
        })
        map_callback("n", config.options.keymaps.attachment_window, mime_buf)()
        local attach_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(attach_buf, 0, -1, false, { attachment })
        vim.api.nvim_set_current_buf(mime_buf)
        map_callback("n", config.options.keymaps.sendmail, mime_buf)()
        H.matches(state.sent[#state.sent], "%-notmuch%-send%-%w%w%w%w%w%w$")
        assert_private_file(state.sent[#state.sent])
        local text = table.concat(vim.fn.readfile(state.sent[#state.sent]), "\n")
        H.contains(text, "Content-Type: multipart/mixed")
        H.contains(text, 'Content-Disposition: attachment; filename="reply-attachment.txt"')
      end)
    end,
  },
  {
    name = "send.sendmail returns false for missing files",
    run = function()
      with_send_env(function(_, send)
        local old_notify = vim.notify
        local note
        vim.notify = function(msg, level)
          note = { msg = msg, level = level }
        end
        local ok, err = pcall(function()
          H.eq(false, send.sendmail("/tmp/notmuch-nvim-missing-message.eml"))
          H.contains(note.msg, "Email file not found")
          H.eq(vim.log.levels.ERROR, note.level)
        end)
        vim.notify = old_notify
        if not ok then
          error(err, 0)
        end
      end)
    end,
  },
  {
    name = "send.sendmail opens terminal, sends msmtp command with logfile, starts insert, and reports success",
    run = function()
      with_send_env(function(state, send, config)
        local file = H.write_file(state.dir .. "/message.eml", "From: a@example.com\n\nbody\n")
        config.options.logfile = state.dir .. "/msmtp.log"

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
          H.eq(true, send.sendmail(file))
          H.ok(term_job, "expected terminal job id")
          H.contains(sent_cmd, "msmtp -t --read-envelope-from")
          H.contains(sent_cmd, "--logfile=" .. vim.fn.shellescape(config.options.logfile))
          H.contains(sent_cmd, "<" .. vim.fn.shellescape(file))
          H.contains(sent_cmd, " ; exit")
          H.list_contains(cmds, "botright 15split | terminal")
          H.list_contains(cmds, "startinsert")
          H.wait_until(function()
            return notes[#notes] and notes[#notes].msg:find("Email sent successfully", 1, true)
          end, 1500)
        end)

        vim.fn.chansend = old_chansend
        vim.cmd = old_cmd
        vim.notify = old_notify
        if not ok then
          error(err, 0)
        end
      end)
    end,
  },
  {
    name = "send.sendmail reports terminal failure exit codes",
    run = function()
      with_send_env(function(state, send, config)
        local file = H.write_file(state.dir .. "/message.eml", "From: a@example.com\n\nbody\n")
        config.options.logfile = nil

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
          H.eq(true, send.sendmail(file))
          H.contains(sent_cmd, "msmtp -t --read-envelope-from")
          H.ok(not sent_cmd:find("--logfile", 1, true), "unexpected logfile option")
          H.wait_until(function()
            return notes[#notes] and notes[#notes].msg:find("exit code: 7", 1, true)
          end, 1500)
          H.eq(vim.log.levels.ERROR, notes[#notes].level)
        end)

        vim.fn.chansend = old_chansend
        vim.notify = old_notify
        if not ok then
          error(err, 0)
        end
      end)
    end,
  },
  {
    name = "send.sendmail runs msmtp in background mode",
    run = function()
      with_send_env(function(state, send, config)
        local content = "From: a@example.com\n\nbody\n"
        local file = H.write_file(state.dir .. "/message.eml", content)
        local logfile = state.dir .. "/smtp log"
        config.options.send.send_mode = "background"
        config.options.logfile = logfile

        local old_system = vim.system
        local old_notify = vim.notify
        local command
        local system_opts
        local success = false
        local notes = {}

        vim.notify = function(msg, level)
          table.insert(notes, { msg = msg, level = level })
        end

        vim.system = function(args, opts, callback)
          command = args
          system_opts = opts
          callback({ code = 0, stdout = "", stderr = "" })
          return {}
        end

        local ok, err = pcall(function()
          H.eq(
            true,
            send.sendmail(file, {
              on_success = function()
                success = true
              end,
            })
          )

          H.same({
            "msmtp",
            "-t",
            "--read-envelope-from",
            "--logfile=" .. logfile,
          }, command)
          H.eq(content, system_opts.stdin)
          H.eq(true, system_opts.text)

          H.wait_until(function()
            return success
          end)
          H.contains(notes[#notes].msg, "Email sent successfully")
        end)

        vim.system = old_system
        vim.notify = old_notify
        if not ok then
          error(err, 0)
        end
      end)
    end,
  },
  {
    name = "send.sendmail reports background failure and invokes callback",
    run = function()
      with_send_env(function(state, send, config)
        local file = H.write_file(state.dir .. "/message.eml", "From: a@example.com\n\nbody\n")
        config.options.send.send_mode = "background"

        local old_system = vim.system
        local old_notify = vim.notify
        local failure_code
        local note

        vim.notify = function(msg, level)
          note = { msg = msg, level = level }
        end
        vim.system = function(_, _, callback)
          callback({ code = 7, stdout = "", stderr = "authentication failed" })
          return {}
        end

        local ok, err = pcall(function()
          H.eq(
            true,
            send.sendmail(file, {
              on_failure = function(code)
                failure_code = code
              end,
            })
          )

          H.wait_until(function()
            return failure_code ~= nil
          end)
          H.eq(7, failure_code)
          H.eq(vim.log.levels.ERROR, note.level)
          H.contains(note.msg, "exit code: 7")
          H.contains(note.msg, "authentication failed")
        end)

        vim.system = old_system
        vim.notify = old_notify
        if not ok then
          error(err, 0)
        end
      end)
    end,
  },
}
