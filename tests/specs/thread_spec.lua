local H = dofile("tests/helpers.lua")

local function msg(id, headers, body, tags)
  return {
    id = id,
    headers = headers or {},
    body = body or {},
    tags = tags or { "inbox" },
    date_relative = "today",
  }
end

local function node(message, replies)
  return { message, replies or {} }
end

local function show_with_json(json_value, fn)
  local old_system = vim.system
  vim.system = function(cmd)
    H.same(
      { "notmuch", "show", "--format=json", "--exclude=false", "--include-html", "thread:fixture" },
      cmd
    )
    return {
      wait = function()
        return { code = 0, stdout = vim.json.encode(json_value) }
      end,
    }
  end
  local ok, err = pcall(fn)
  vim.system = old_system
  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "thread.show_thread renders a single plain-text message with headers",
    run = function()
      local thread = require("notmuch.thread")
      local json = {
        {
          node(msg("m1", {
            Subject = "Hello",
            From = "Alice <alice@example.com>",
            To = "Bob <bob@example.com>",
            Cc = "Carol <carol@example.com>",
            Date = "Mon, 1 Jan 2024 00:00:00 +0000",
          }, {
            { ["content-type"] = "text/plain", content = "Line one\nLine two" },
          }, { "inbox", "unread" })),
        },
      }

      show_with_json(json, function()
        local lines, metadata = thread.show_thread("fixture")
        H.contains(lines, "Alice <alice@example.com> (today) (inbox unread)")
        H.contains(lines, "id:m1 {{{")
        H.contains(lines, "Subject: Hello")
        H.contains(lines, "From: Alice <alice@example.com>")
        H.contains(lines, "To: Bob <bob@example.com>")
        H.contains(lines, "Cc: Carol <carol@example.com>")
        H.contains(lines, "Date: Mon, 1 Jan 2024 00:00:00 +0000")
        H.contains(lines, "Line one")
        H.contains(lines, "Line two")
        H.contains(lines, "}}}")
        H.eq("fixture", metadata.thread.id)
        H.eq("Hello", metadata.thread.subject)
        H.eq(1, metadata.thread.message_count)
        H.same({ "inbox", "unread" }, metadata.thread.tags)
        H.same({ "Alice <alice@example.com>" }, metadata.thread.authors)
        H.eq(0, metadata.messages[1].attachment_count)
      end)
    end,
  },
  {
    name = "thread.show_thread renders replies with depth indentation and metadata positions",
    run = function()
      local thread = require("notmuch.thread")
      local json = {
        {
          node(
            msg("root", { Subject = "Root", From = "Root <r@example.com>", Date = "date" }, {
              { ["content-type"] = "text/plain", content = "root body" },
            }),
            {
              node(
                msg(
                  "reply",
                  { Subject = "Re: Root", From = "Reply <r@example.com>", Date = "date" },
                  {
                    { ["content-type"] = "text/plain", content = "reply body" },
                  },
                  { "sent" }
                )
              ),
            }
          ),
        },
      }

      show_with_json(json, function()
        local lines, metadata = thread.show_thread("fixture")
        H.contains(lines, "Root <r@example.com> (today) (inbox)")
        H.contains(lines, "────Reply <r@example.com> (today) (sent)")
        H.eq(2, metadata.thread.message_count)
        H.eq("root", metadata.messages[1].id)
        H.eq("reply", metadata.messages[2].id)
        H.eq(0, metadata.messages[1].depth)
        H.eq(1, metadata.messages[2].depth)
        H.ok(metadata.messages[1].start_line < metadata.messages[1].end_line)
        H.ok(metadata.messages[2].start_line > metadata.messages[1].end_line)
      end)
    end,
  },
  {
    name = "thread.show_thread uses fallbacks for missing headers",
    run = function()
      local thread = require("notmuch.thread")
      local json = {
        {
          node(msg("missing", {}, {
            { ["content-type"] = "text/plain", content = "body" },
          }, {})),
        },
      }

      show_with_json(json, function()
        local lines, metadata = thread.show_thread("fixture")
        H.contains(lines, "[Unknown sender] (today) ()")
        H.contains(lines, "Subject: [No subject]")
        H.contains(lines, "From: [Unknown sender]")
        H.contains(lines, "Date: ")
        H.eq("[No subject]", metadata.thread.subject)
      end)
    end,
  },
  {
    name = "thread.show_thread recurses multipart bodies and marks attachments/inline parts",
    run = function()
      local thread = require("notmuch.thread")
      local json = {
        {
          node(msg("mime", { Subject = "Mime", From = "A <a@example.com>", Date = "date" }, {
            {
              ["content-type"] = "multipart/mixed",
              content = {
                { ["content-type"] = "text/plain", content = "plain body" },
                { ["content-type"] = "application/pdf", filename = "file.pdf", content = "..." },
                { ["content-type"] = "image/png", content = "inline bytes" },
              },
            },
          })),
        },
      }

      show_with_json(json, function()
        local lines, metadata = thread.show_thread("fixture")
        H.contains(lines, "plain body")
        H.contains(lines, "📎 1 attachment")
        H.contains(lines, "[ 📎 file.pdf (application/pdf) - press 'a' to view attachments ]")
        H.contains(lines, "[ image/png (inline) - press 'a' to view attachments ]")
        H.eq(1, metadata.messages[1].attachment_count)
      end)
    end,
  },
  {
    name = "thread.show_thread handles multipart alternative and hidden html when rendering disabled",
    run = function()
      local thread = require("notmuch.thread")
      local config = require("notmuch.config")
      config.options.render_html_body = false
      local json = {
        {
          node(msg("alt", { Subject = "Alt", From = "A <a@example.com>", Date = "date" }, {
            {
              ["content-type"] = "multipart/alternative",
              content = {
                { ["content-type"] = "text/plain", content = "plain version" },
                { ["content-type"] = "text/html", content = "<b>html version</b>" },
              },
            },
            { ["content-type"] = "text/html", content = "<p>hidden html</p>" },
          })),
        },
      }

      show_with_json(json, function()
        local lines = thread.show_thread("fixture")
        H.contains(lines, "plain version")
        H.contains(lines, "[ text/html (alternative) - press 'a' to view ]")
        H.contains(lines, "[ text/html (hidden) - press 'a' to view ]")
      end)
    end,
  },
  {
    name = "thread.show_thread renders html through w3m or reports missing/failed renderer",
    run = function()
      local thread = require("notmuch.thread")
      local config = require("notmuch.config")
      local old_executable = vim.fn.executable
      local old_system = vim.system
      config.options.render_html_body = true
      local json = {
        {
          node(msg("html", { Subject = "Html", From = "A <a@example.com>", Date = "date" }, {
            { ["content-type"] = "text/html", content = "<b>Hello</b>" },
          })),
        },
      }

      vim.fn.executable = function(name)
        return name == "w3m" and 0 or old_executable(name)
      end
      show_with_json(json, function()
        local lines = thread.show_thread("fixture")
        H.contains(lines, "[ w3m not installed - press 'a' to view attachments ]")
      end)

      vim.fn.executable = function(name)
        return name == "w3m" and 1 or old_executable(name)
      end
      vim.system = function(cmd, opts)
        if cmd[1] == "w3m" then
          H.eq("<b>Hello</b>", opts.stdin)
          return {
            wait = function()
              return { code = 0, stdout = "Hello\n" }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0, stdout = vim.json.encode(json) }
          end,
        }
      end
      local lines = thread.show_thread("fixture")
      H.contains(lines, "Hello")

      vim.system = function(cmd)
        if cmd[1] == "w3m" then
          return {
            wait = function()
              return { code = 1, stdout = "", stderr = "boom" }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0, stdout = vim.json.encode(json) }
          end,
        }
      end
      lines = thread.show_thread("fixture")
      H.contains(lines, "[ Failed to render HTML - press 'a' to view attachments ]")

      vim.fn.executable = old_executable
      vim.system = old_system
      config.options.render_html_body = false
    end,
  },
  {
    name = "thread cursor tracking updates current message and status",
    run = function()
      local thread = require("notmuch.thread")
      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.b.notmuch_messages = {
        {
          id = "m1",
          start_line = 3,
          end_line = 6,
          from = "Alice <a@example.com>",
          attachment_count = 0,
        },
        {
          id = "m2",
          start_line = 8,
          end_line = 12,
          from = "Bob <b@example.com>",
          attachment_count = 2,
        },
      }
      vim.api.nvim_buf_set_lines(
        buf,
        0,
        -1,
        false,
        { "Hints", "", "m1", "body", "", "}}}", "", "m2", "body", "", "", "}}}" }
      )
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      thread.setup_cursor_tracking(buf)
      H.eq("m1", vim.b.notmuch_current.id)
      H.eq("1/2 Alice", vim.b.notmuch_status)
      vim.api.nvim_win_set_cursor(0, { 8, 0 })
      vim.cmd("doautocmd CursorMoved")
      H.eq("m2", vim.b.notmuch_current.id)
      H.eq("2/2 Bob 📎2", vim.b.notmuch_status)
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
}
