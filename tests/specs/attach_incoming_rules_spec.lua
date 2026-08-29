local H = dofile("tests/helpers.lua")

local function attachment(overrides)
  local att = {
    path = "/tmp/doc.pdf",
    part = {
      id = 2,
      content_type = "application/pdf",
      filename = "doc.pdf",
      disposition = "attachment",
      size = 123,
      ext = "pdf",
    },
    message = {
      id = "msg-1",
    },
  }

  overrides = overrides or {}
  for key, value in pairs(overrides) do
    if key == "part" then
      for part_key, part_value in pairs(value) do
        att.part[part_key] = part_value
      end
    elseif key == "message" then
      for msg_key, msg_value in pairs(value) do
        att.message[msg_key] = msg_value
      end
    else
      att[key] = value
    end
  end

  return att
end

local function rule_names(ruleset)
  local names = {}
  for _, rule in ipairs(ruleset) do
    names[#names + 1] = rule.name
  end
  return names
end

return {
  {
    name = "attach.incoming.rules.matches supports wildcard matchers",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      H.eq(true, rules.matches({ name = "all", match = "*" }, attachment()))
      H.eq(false, rules.matches({ name = "none" }, attachment()))
      H.eq(false, rules.matches(nil, attachment()))
    end,
  },
  {
    name = "attach.incoming.rules.matches uses AND semantics for structured matchers",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local att = attachment()

      H.eq(
        true,
        rules.matches({
          name = "pdf",
          match = {
            content_type = "application/pdf",
            ext = "pdf",
            filename = "doc.pdf",
            disposition = "attachment",
            id = 2,
            size = 123,
            message_id = "msg-1",
          },
        }, att)
      )

      H.eq(
        false,
        rules.matches({
          name = "not-pdf",
          match = {
            content_type = "application/pdf",
            ext = "txt",
          },
        }, att)
      )

      H.eq(
        false,
        rules.matches({
          name = "unknown-key",
          match = {
            unknown = "value",
          },
        }, att)
      )
    end,
  },
  {
    name = "attach.incoming.rules.matches supports function matchers",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local att = attachment()

      H.eq(
        true,
        rules.matches({
          name = "function-true",
          match = function(candidate)
            return candidate.part.filename == "doc.pdf"
          end,
        }, att)
      )

      H.eq(
        false,
        rules.matches({
          name = "function-false",
          match = function(candidate)
            return candidate.part.filename == "other.pdf"
          end,
        }, att)
      )
    end,
  },
  {
    name = "attach.incoming.rules.matches reports and skips matcher errors",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local old_notify = vim.notify
      local note
      vim.notify = function(msg, level)
        note = { msg = msg, level = level }
      end

      local ok, matched = pcall(rules.matches, {
        name = "broken",
        match = function()
          error("matcher exploded")
        end,
      }, attachment())

      vim.notify = old_notify
      H.eq(true, ok)
      H.eq(false, matched)
      H.contains(note.msg, 'attachment rule "broken" matcher failed')
      H.contains(note.msg, "matcher exploded")
      H.eq(vim.log.levels.ERROR, note.level)
    end,
  },
  {
    name = "attach.incoming.rules.matches supports MIME prefix wildcards",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local image =
        attachment({ part = { content_type = "image/png", ext = "png", filename = "img.png" } })
      local pdf = attachment()

      H.eq(true, rules.matches({ name = "image", match = { content_type = "image/*" } }, image))
      H.eq(false, rules.matches({ name = "image", match = { content_type = "image/*" } }, pdf))
    end,
  },
  {
    name = "attach.incoming.rules.first_match returns first matching rule and index",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local att = attachment()
      local matched, index = rules.first_match({
        { name = "txt", match = { ext = "txt" } },
        { name = "pdf", match = { ext = "pdf" } },
        { name = "all", match = "*" },
      }, att)

      H.eq("pdf", matched.name)
      H.eq(2, index)

      matched, index = rules.first_match({
        { name = "txt", match = { ext = "txt" } },
      }, att)
      H.eq(nil, matched)
      H.eq(nil, index)
    end,
  },
  {
    name = "attach.incoming.rules.expand_command expands static argv commands",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local argv, err = rules.expand_command({ "pdftotext", "$path", "-" }, attachment())

      H.eq(nil, err)
      H.same({ "pdftotext", "/tmp/doc.pdf", "-" }, argv)
    end,
  },
  {
    name = "attach.incoming.rules.expand_command does not expand embedded placeholders",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local argv, err = rules.expand_command({ "echo", "file=$path" }, attachment())

      H.eq(nil, err)
      H.same({ "echo", "file=$path" }, argv)
    end,
  },
  {
    name = "attach.incoming.rules.expand_command supports function commands",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local argv, err = rules.expand_command(function(att)
        return { "open", att.path }
      end, attachment())

      H.eq(nil, err)
      H.same({ "open", "/tmp/doc.pdf" }, argv)
    end,
  },
  {
    name = "attach.incoming.rules.expand_command reports validation errors",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local argv, err

      argv, err = rules.expand_command("xdg-open", attachment())
      H.eq(nil, argv)
      H.contains(err, "command must be a table or function")

      local missing_path = attachment()
      missing_path.path = nil
      argv, err = rules.expand_command({ "xdg-open", "$path" }, missing_path)
      H.eq(nil, argv)
      H.contains(err, "attachment.path is nil")

      argv, err = rules.expand_command(function()
        return "not-a-table"
      end, attachment())
      H.eq(nil, argv)
      H.contains(err, "expanded command is empty")

      argv, err = rules.expand_command({}, attachment())
      H.eq(nil, argv)
      H.contains(err, "expanded command is empty")
    end,
  },
  {
    name = "attach.incoming.rules.apply_patches applies prepend replace disable and append in order",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local defaults = {
        { name = "html", match = { content_type = "text/html" } },
        { name = "pdf", match = { content_type = "application/pdf" } },
        { name = "text", match = { content_type = "text/*" } },
      }

      local effective = rules.apply_patches(defaults, {
        prepend = {
          { name = "custom-first", match = "*" },
        },
        replace = {
          pdf = { name = "pdf-custom", match = { ext = "pdf" } },
          missing = { name = "missing-custom", match = "*" },
        },
        disable = { "html" },
        append = {
          { name = "custom-last", match = "*" },
        },
      })

      H.same({ "custom-first", "pdf-custom", "text", "custom-last" }, rule_names(effective))
    end,
  },
  {
    name = "attach.incoming.rules.apply_patches does not mutate default rules",
    run = function()
      local rules = require("notmuch.attach.incoming.rules")
      local defaults = {
        { name = "html" },
        { name = "pdf" },
        { name = "text" },
      }

      local effective = rules.apply_patches(defaults, {
        replace = {
          pdf = { name = "pdf-custom" },
        },
        disable = { "html" },
      })

      H.same({ "html", "pdf", "text" }, rule_names(defaults))
      H.same({ "pdf-custom", "text" }, rule_names(effective))
    end,
  },
}
