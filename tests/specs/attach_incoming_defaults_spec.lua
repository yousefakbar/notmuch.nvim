local H = dofile("tests/helpers.lua")

local function rule_names(ruleset)
  local names = {}
  for _, rule in ipairs(ruleset) do
    names[#names + 1] = rule.name
  end
  return names
end

local function find_rule(ruleset, name)
  for _, rule in ipairs(ruleset) do
    if rule.name == name then
      return rule
    end
  end
  error("missing rule: " .. name, 2)
end

local function att(fields)
  fields = fields or {}
  local part = fields.part or {}
  local message = fields.message or {}

  return {
    path = fields.path or "/tmp/attachment",
    part = {
      id = part.id or 1,
      content_type = part.content_type or "application/octet-stream",
      filename = part.filename or "",
      disposition = part.disposition or "attachment",
      size = part.size or 0,
      ext = part.ext or "",
    },
    message = {
      id = message.id or "msg-1",
    },
  }
end

return {
  {
    name = "attach.incoming.defaults.open_rules includes system opener with vim.ui.open handler and command fallback",
    run = function()
      local defaults = require("notmuch.attach.incoming.defaults")
      local open_rules = defaults.open_rules()

      H.eq(1, #open_rules)
      local rule = open_rules[1]
      H.eq("system", rule.name)
      H.eq("*", rule.match)
      H.eq("function", type(rule.handler))
      H.eq(true, rule.detach)
      H.contains(rule.fallback, "Could not open attachment")

      local sysname = vim.uv.os_uname().sysname
      local expected = (sysname == "Darwin" and "open")
        or (sysname == "Linux" and "xdg-open")
        or (sysname:match("Windows") and "start")
        or "xdg-open"

      H.same({ expected, "$path" }, rule.command)
    end,
  },
  {
    name = "attach.incoming.defaults.view_rules returns expected rules in priority order",
    run = function()
      local defaults = require("notmuch.attach.incoming.defaults")
      H.same({
        "html",
        "pdf",
        "image",
        "office",
        "markdown",
        "zip",
        "tar",
        "text",
        "binary",
      }, rule_names(defaults.view_rules()))
    end,
  },
  {
    name = "attach.incoming.defaults returns fresh rule tables",
    run = function()
      local defaults = require("notmuch.attach.incoming.defaults")

      local view_a = defaults.view_rules()
      local view_b = defaults.view_rules()
      view_a[1].name = "mutated"
      view_a[2].commands[1][1] = "mutated-command"
      H.eq("html", view_b[1].name)
      H.eq("pdftotext", view_b[2].commands[1][1])

      local open_a = defaults.open_rules()
      local open_b = defaults.open_rules()
      open_a[1].name = "mutated"
      open_a[1].command[1] = "mutated-command"
      H.eq("system", open_b[1].name)
      H.eq("$path", open_b[1].command[2])
    end,
  },
  {
    name = "attach.incoming.defaults.view_rules preserve default command chains",
    run = function()
      local defaults = require("notmuch.attach.incoming.defaults")
      local view_rules = defaults.view_rules()

      H.same(
        { "w3m", "-T", "text/html", "-dump", "$path" },
        find_rule(view_rules, "html").commands[1]
      )
      H.same({ "lynx", "-dump", "-nolist", "$path" }, find_rule(view_rules, "html").commands[2])
      H.same(
        { "elinks", "-dump", "-no-references", "$path" },
        find_rule(view_rules, "html").commands[3]
      )

      H.same({ "pdftotext", "-layout", "$path", "-" }, find_rule(view_rules, "pdf").commands[1])
      H.same({ "mutool", "draw", "-F", "txt", "$path" }, find_rule(view_rules, "pdf").commands[2])

      H.same({ "chafa", "--size", "80x40", "$path" }, find_rule(view_rules, "image").commands[1])
      H.same({ "catimg", "-w", "80", "$path" }, find_rule(view_rules, "image").commands[2])
      H.same({ "viu", "-w", "80", "$path" }, find_rule(view_rules, "image").commands[3])
      H.same({ "exiftool", "$path" }, find_rule(view_rules, "image").commands[4])
      H.same({ "identify", "-verbose", "$path" }, find_rule(view_rules, "image").commands[5])

      H.same({ "pandoc", "-t", "plain", "$path" }, find_rule(view_rules, "office").commands[1])
      H.same({ "docx2txt", "$path", "-" }, find_rule(view_rules, "office").commands[2])

      H.same({ "pandoc", "-t", "plain", "$path" }, find_rule(view_rules, "markdown").commands[1])
      H.same({ "mdcat", "$path" }, find_rule(view_rules, "markdown").commands[2])
      H.same({ "cat", "$path" }, find_rule(view_rules, "markdown").commands[3])

      H.same({ "unzip", "-l", "$path" }, find_rule(view_rules, "zip").commands[1])
      H.same({ "tar", "-tvf", "$path" }, find_rule(view_rules, "tar").commands[1])
      H.same({ "cat", "$path" }, find_rule(view_rules, "text").commands[1])
      H.same({ "strings", "$path" }, find_rule(view_rules, "binary").commands[1])
    end,
  },
  {
    name = "attach.incoming.defaults.view_rules match representative attachments",
    run = function()
      local defaults = require("notmuch.attach.incoming.defaults")
      local rules = require("notmuch.attach.incoming.rules")
      local view_rules = defaults.view_rules()

      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "html"),
          att({ part = { content_type = "text/html", filename = "body.html", ext = "html" } })
        )
      )
      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "pdf"),
          att({ part = { content_type = "application/pdf", filename = "doc.pdf", ext = "pdf" } })
        )
      )
      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "pdf"),
          att({
            part = { content_type = "application/octet-stream", filename = "doc.pdf", ext = "pdf" },
          })
        )
      )
      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "image"),
          att({ part = { content_type = "image/png", filename = "img.png", ext = "png" } })
        )
      )
      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "office"),
          att({
            part = {
              content_type = "application/octet-stream",
              filename = "doc.docx",
              ext = "docx",
            },
          })
        )
      )
      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "markdown"),
          att({ part = { content_type = "text/markdown", filename = "README.md", ext = "md" } })
        )
      )
      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "zip"),
          att({ part = { content_type = "application/zip", filename = "archive.zip", ext = "zip" } })
        )
      )
      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "tar"),
          att({
            part = { content_type = "application/gzip", filename = "archive.tar.gz", ext = "gz" },
          })
        )
      )
      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "text"),
          att({ part = { content_type = "text/plain", filename = "note.txt", ext = "txt" } })
        )
      )
      H.eq(
        true,
        rules.matches(
          find_rule(view_rules, "binary"),
          att({
            part = { content_type = "application/octet-stream", filename = "blob.bin", ext = "bin" },
          })
        )
      )
    end,
  },
  {
    name = "attach.incoming.defaults.view_rules expose fallback messages",
    run = function()
      local defaults = require("notmuch.attach.incoming.defaults")
      local view_rules = defaults.view_rules()

      H.contains(find_rule(view_rules, "html").fallback, "HTML file")
      H.contains(find_rule(view_rules, "pdf").fallback, "PDF file")
      H.contains(find_rule(view_rules, "image").fallback, "Image file")
      H.eq("function", type(find_rule(view_rules, "binary").fallback))

      local fallback = find_rule(view_rules, "binary").fallback(att({
        path = "/tmp/blob.bin",
        part = { content_type = "application/octet-stream" },
      }))
      H.contains(fallback, "Unable to view binary file")
      H.contains(fallback, "application/octet-stream")
      H.contains(fallback, "/tmp/blob.bin")
    end,
  },
}
