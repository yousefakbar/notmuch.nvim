local H = dofile("tests/helpers.lua")

local function with_mocked_notmuch_config(values, fn)
  local old_system = vim.fn.system
  vim.fn.system = function(cmd)
    local key = tostring(cmd):match("notmuch config get%s+(.+)$")
    local value = key and values[key]
    if value == false or value == nil then
      return old_system("false")
    end
    return old_system("printf %s " .. vim.fn.shellescape(value .. "\n"))
  end
  local ok, err = pcall(fn)
  vim.fn.system = old_system
  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "config.setup succeeds with valid notmuch config and applies fallbacks/options",
    run = function()
      local config = require("notmuch.config")
      local notes = {}
      local old_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notes, { msg = msg, level = level })
      end

      with_mocked_notmuch_config({
        ["database.path"] = "/tmp/notmuch-db",
        ["user.name"] = false,
        ["user.primary_email"] = false,
      }, function()
        H.eq(true, config.setup({
          notmuch_db_path = "~/custom-db",
          maildir_sync_cmd = "true",
          sync = { sync_mode = "background" },
          drafts = { auto_open_attachment_window = true },
          keymaps = { sendmail = "<F5>" },
        }))
        H.eq(vim.fn.expand("~/custom-db"), config.options.notmuch_db_path)
        H.eq("User <user@localhost>", config.options.from)
        H.eq("background", config.options.sync.sync_mode)
        H.eq(true, config.options.drafts.auto_open_attachment_window)
        H.eq("<F5>", config.options.keymaps.sendmail)
        H.eq("<C-g><C-a>", config.options.keymaps.attachment_window)
      end)

      H.ok(#notes > 0, "expected warning for missing user identity")
      H.eq(vim.log.levels.WARN, notes[1].level)
      vim.notify = old_notify
    end,
  },
  {
    name = "config.setup defaults draft attachment window auto-open to false",
    run = function()
      local config = require("notmuch.config")
      with_mocked_notmuch_config({
        ["database.path"] = "/tmp/notmuch-db",
        ["user.name"] = "Tester",
        ["user.primary_email"] = "tester@example.com",
      }, function()
        H.eq(true, config.setup({}))
        H.eq(false, config.options.drafts.auto_open_attachment_window)
      end)
    end,
  },
  {
    name = "config.setup provides incoming attachment config defaults",
    run = function()
      local config = require("notmuch.config")
      with_mocked_notmuch_config({
        ["database.path"] = "/tmp/notmuch-db",
        ["user.name"] = "Tester",
        ["user.primary_email"] = "tester@example.com",
      }, function()
        H.eq(true, config.setup({}))

        local incoming = config.options.attach.incoming
        H.ok(incoming.cache_dir)
        H.contains(incoming.cache_dir, "notmuch.nvim")
        H.contains(incoming.cache_dir, "attachments")

        H.same({}, incoming.open.rules.prepend)
        H.same({}, incoming.open.rules.append)
        H.same({}, incoming.open.rules.replace)
        H.same({}, incoming.open.rules.disable)

        H.same({}, incoming.view.rules.prepend)
        H.same({}, incoming.view.rules.append)
        H.same({}, incoming.view.rules.replace)
        H.same({}, incoming.view.rules.disable)

        H.eq("float", incoming.view.window.type)
        H.eq(0.8, incoming.view.window.width)
        H.eq(0.8, incoming.view.window.height)
        H.eq("rounded", incoming.view.window.border)
      end)
    end,
  },
  {
    name = "config.setup merges incoming attachment rule patches",
    run = function()
      local config = require("notmuch.config")
      with_mocked_notmuch_config({
        ["database.path"] = "/tmp/notmuch-db",
        ["user.name"] = "Tester",
        ["user.primary_email"] = "tester@example.com",
      }, function()
        H.eq(true, config.setup({
          attach = {
            incoming = {
              open = {
                rules = {
                  prepend = {
                    {
                      name = "pdf-zathura",
                      match = { ext = "pdf" },
                      command = { "zathura", "$path" },
                      detach = true,
                    },
                  },
                },
              },
              view = {
                rules = {
                  disable = { "pdf" },
                  replace = {
                    html = {
                      name = "html",
                      match = { content_type = "text/html" },
                      commands = {
                        { "custom-html", "$path" },
                      },
                    },
                  },
                },
              },
            },
          },
        }))

        local incoming = config.options.attach.incoming
        local open_rule = incoming.open.rules.prepend[1]
        H.eq("pdf-zathura", open_rule.name)
        H.same({ "zathura", "$path" }, open_rule.command)
        H.eq(true, open_rule.detach)

        H.same({ "pdf" }, incoming.view.rules.disable)
        H.eq("html", incoming.view.rules.replace.html.name)
        H.same({ "custom-html", "$path" }, incoming.view.rules.replace.html.commands[1])
        H.same({}, incoming.view.rules.prepend)
        H.same({}, incoming.view.rules.append)
      end)
    end,
  },
  {
    name = "config.setup maps attachment shorthand to incoming rule config",
    run = function()
      local config = require("notmuch.config")
      with_mocked_notmuch_config({
        ["database.path"] = "/tmp/notmuch-db",
        ["user.name"] = "Tester",
        ["user.primary_email"] = "tester@example.com",
      }, function()
        H.eq(true, config.setup({
          attachments = {
            cache_dir = "~/notmuch-shorthand-cache",
            open = {
              {
                name = "pdf-firefox",
                match = { ext = "pdf" },
                command = { "firefox", "$path" },
                detach = true,
                fallback = "Could not open PDF with Firefox",
              },
            },
            view = {
              {
                name = "pdf-text",
                match = { content_type = "application/pdf" },
                commands = {
                  { "pdftotext", "-raw", "$path", "-" },
                },
                filetype = "text",
                fallback = "Install pdftotext to preview PDFs.",
              },
            },
            window = {
              width = 0.9,
              height = 0.7,
              border = "single",
            },
          },
        }))

        local incoming = config.options.attach.incoming
        H.eq(vim.fn.expand("~/notmuch-shorthand-cache"), incoming.cache_dir)

        local open_rule = incoming.open.rules.prepend[1]
        H.eq("pdf-firefox", open_rule.name)
        H.same({ ext = "pdf" }, open_rule.match)
        H.same({ "firefox", "$path" }, open_rule.command)
        H.eq(true, open_rule.detach)
        H.eq("Could not open PDF with Firefox", open_rule.fallback)

        local view_rule = incoming.view.rules.prepend[1]
        H.eq("pdf-text", view_rule.name)
        H.same({ content_type = "application/pdf" }, view_rule.match)
        H.same({ "pdftotext", "-raw", "$path", "-" }, view_rule.commands[1])
        H.eq("text", view_rule.filetype)
        H.eq("Install pdftotext to preview PDFs.", view_rule.fallback)

        H.eq(0.9, incoming.view.window.width)
        H.eq(0.7, incoming.view.window.height)
        H.eq("single", incoming.view.window.border)
      end)
    end,
  },
  {
    name = "config.setup does not expose legacy incoming attachment handlers by default",
    run = function()
      local config = require("notmuch.config")
      with_mocked_notmuch_config({
        ["database.path"] = "/tmp/notmuch-db",
        ["user.name"] = "Tester",
        ["user.primary_email"] = "tester@example.com",
      }, function()
        H.eq(true, config.setup({}))
        H.eq(nil, config.options.open_handler)
        H.eq(nil, config.options.view_handler)
      end)
    end,
  },
  {
    name = "config.setup expands incoming attachment cache directory",
    run = function()
      local config = require("notmuch.config")
      with_mocked_notmuch_config({
        ["database.path"] = "/tmp/notmuch-db",
        ["user.name"] = "Tester",
        ["user.primary_email"] = "tester@example.com",
      }, function()
        H.eq(true, config.setup({
          attach = {
            incoming = {
              cache_dir = "~/notmuch-test-cache",
            },
          },
        }))

        H.eq(vim.fn.expand("~/notmuch-test-cache"), config.options.attach.incoming.cache_dir)
      end)
    end,
  },
  {
    name = "config.setup fails gracefully when database.path is missing",
    run = function()
      local config = require("notmuch.config")
      local old_notify = vim.notify
      local notes = {}
      vim.notify = function(msg, level)
        table.insert(notes, { msg = msg, level = level })
      end

      with_mocked_notmuch_config({
        ["database.path"] = false,
        ["user.name"] = "Tester",
        ["user.primary_email"] = "tester@example.com",
      }, function()
        H.eq(false, config.setup({}))
      end)

      H.ok(#notes >= 2, "expected database-path error notifications")
      H.eq(vim.log.levels.ERROR, notes[1].level)
      H.contains(notes[1].msg, "database.path not configured")
      vim.notify = old_notify
    end,
  },
  {
    name = "notmuch.setup does not register commands if config setup fails",
    run = function()
      for _, cmd in ipairs({ "Notmuch", "NotmuchDrafts", "NmSearch", "Inbox", "ComposeMail" }) do
        pcall(vim.api.nvim_del_user_command, cmd)
      end

      local nm = require("notmuch")
      local config = require("notmuch.config")
      local old_setup = config.setup
      local ok, err = pcall(function()
        config.setup = function()
          return false
        end
        nm.setup({})
        config.setup = old_setup

        local commands = vim.api.nvim_get_commands({})
        H.eq(nil, commands.Notmuch)
        H.eq(nil, commands.NmSearch)
        H.eq(nil, commands.Inbox)
        H.eq(nil, commands.ComposeMail)
      end)
      config.setup = old_setup

      nm.setup({
        notmuch_db_path = vim.fn.getcwd() .. "/tests/tmp/mail",
        maildir_sync_cmd = "true",
        render_html_body = false,
        suppress_deprecation_warning = true,
      })

      if not ok then
        error(err, 0)
      end
    end,
  },
}
