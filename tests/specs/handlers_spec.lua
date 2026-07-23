local H = dofile("tests/helpers.lua")

local function with_view_mocks(mime_type, ext_path, available, results, fn)
  local old_executable = vim.fn.executable
  local old_system_fn = vim.fn.system
  local old_system = vim.system
  local calls = {}

  vim.fn.executable = function(tool)
    return available[tool] and 1 or 0
  end
  vim.fn.system = function(cmd)
    calls[#calls + 1] = cmd
    if type(cmd) == "table" and cmd[1] == "file" then
      return mime_type .. "\n"
    end
    if type(cmd) == "table" then
      local key = table.concat(cmd, " ")
      return results[key] and results[key].stdout or "fn-system output"
    end
    return "fn-system output"
  end
  vim.system = function(cmd)
    calls[#calls + 1] = cmd
    local key = table.concat(cmd, " ")
    local result = results[key] or { code = 0, stdout = cmd[1] .. " output" }
    return {
      wait = function()
        return result
      end,
    }
  end

  local ok, err = pcall(fn, calls, ext_path)
  vim.fn.executable = old_executable
  vim.fn.system = old_system_fn
  vim.system = old_system
  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "handlers.default_open_handler uses vim.ui.open when available",
    run = function()
      local handlers = require("notmuch.handlers")
      local old_open = vim.ui.open
      local opened

      vim.ui.open = function(path)
        opened = path
        return {
          wait = function()
            return { code = 0 }
          end,
        },
          nil
      end

      handlers.default_open_handler({ path = "/tmp/file.txt" })

      H.eq("/tmp/file.txt", opened)
      vim.ui.open = old_open
    end,
  },
  {
    name = "handlers.default_open_handler reports vim.ui.open failures",
    run = function()
      local handlers = require("notmuch.handlers")
      local old_open = vim.ui.open
      local old_notify = vim.notify
      local note

      vim.ui.open = function()
        return nil, "no opener found"
      end
      vim.notify = function(msg, level)
        note = { msg = msg, level = level }
      end

      handlers.default_open_handler({ path = "/tmp/file.txt" })

      H.contains(note.msg, "failed to open attachment")
      H.contains(note.msg, "no opener found")
      H.eq(vim.log.levels.ERROR, note.level)

      vim.ui.open = old_open
      vim.notify = old_notify
    end,
  },
  {
    name = "handlers.default_open_handler falls back to OS opener without vim.ui.open",
    run = function()
      local handlers = require("notmuch.handlers")
      local old_open = vim.ui.open
      local old_system = vim.system
      local captured_cmd, captured_opts

      vim.ui.open = nil
      vim.system = function(cmd, opts)
        captured_cmd = cmd
        captured_opts = opts
        return {
          wait = function()
            return { code = 0, stdout = "" }
          end,
        }
      end

      handlers.default_open_handler({ path = "/tmp/file.txt" })

      local sysname = vim.uv.os_uname().sysname
      local expected = (sysname == "Darwin" and "open")
        or (sysname == "Linux" and "xdg-open")
        or (sysname:match("Windows") and "start")
        or "xdg-open"

      H.same({ expected, "/tmp/file.txt" }, captured_cmd)
      H.same({ detach = true }, captured_opts)

      vim.ui.open = old_open
      vim.system = old_system
    end,
  },
  {
    name = "handlers.default_view_handler reads plain text attachments",
    run = function()
      local handlers = require("notmuch.handlers")
      local dir = H.tmpdir()
      local file = H.write_file(dir .. "/note.txt", "hello viewer\n")

      local output = handlers.default_view_handler({ path = file })
      H.contains(output, "hello viewer")
    end,
  },
  {
    name = "handlers.default_view_handler uses preferred viewers by MIME type",
    run = function()
      local handlers = require("notmuch.handlers")
      local cases = {
        {
          mime = "text/html",
          path = "/tmp/page.html",
          tools = { "w3m", "lynx", "elinks" },
          expected = { "w3m", "-T", "text/html", "-dump", "/tmp/page.html" },
        },
        {
          mime = "application/pdf",
          path = "/tmp/doc.pdf",
          tools = { "pdftotext", "mutool" },
          expected = { "pdftotext", "-layout", "/tmp/doc.pdf", "-" },
        },
        {
          mime = "image/png",
          path = "/tmp/img.png",
          tools = { "chafa", "catimg", "viu", "exiftool", "identify" },
          expected = { "chafa", "--size", "80x40", "/tmp/img.png" },
        },
        {
          mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          path = "/tmp/doc.docx",
          tools = { "pandoc", "docx2txt" },
          expected = { "pandoc", "-t", "plain", "/tmp/doc.docx" },
        },
        {
          mime = "text/markdown",
          path = "/tmp/readme.md",
          tools = { "pandoc", "mdcat" },
          expected = { "pandoc", "-t", "plain", "/tmp/readme.md" },
        },
      }

      for _, case in ipairs(cases) do
        local available = {}
        for _, tool in ipairs(case.tools) do
          available[tool] = true
        end
        with_view_mocks(case.mime, case.path, available, {}, function(calls)
          local output = handlers.default_view_handler({ path = case.path })
          H.contains(output, case.expected[1] .. " output")
          H.same(case.expected, calls[2])
        end)
      end
    end,
  },
  {
    name = "handlers.default_view_handler falls back through viewer chains",
    run = function()
      local handlers = require("notmuch.handlers")
      with_view_mocks("text/html", "/tmp/page.html", { w3m = true, lynx = true }, {
        ["w3m -T text/html -dump /tmp/page.html"] = { code = 1, stdout = "" },
        ["lynx -dump -nolist /tmp/page.html"] = { code = 0, stdout = "lynx rendered" },
      }, function(calls)
        H.eq("lynx rendered", handlers.default_view_handler({ path = "/tmp/page.html" }))
        H.same({ "w3m", "-T", "text/html", "-dump", "/tmp/page.html" }, calls[2])
        H.same({ "lynx", "-dump", "-nolist", "/tmp/page.html" }, calls[3])
      end)
    end,
  },
  {
    name = "handlers.default_view_handler handles archives, markdown cat fallback, binary strings, and no-viewer fallback",
    run = function()
      local handlers = require("notmuch.handlers")

      with_view_mocks("application/zip", "/tmp/archive.zip", {}, {
        ["unzip -l /tmp/archive.zip"] = { code = 0, stdout = "zip listing" },
      }, function(calls)
        H.eq("zip listing", handlers.default_view_handler({ path = "/tmp/archive.zip" }))
        H.same({ "unzip", "-l", "/tmp/archive.zip" }, calls[2])
      end)

      with_view_mocks("application/x-tar", "/tmp/archive.tar", {}, {
        ["tar -tvf /tmp/archive.tar"] = { code = 0, stdout = "tar listing" },
      }, function(calls)
        H.eq("tar listing", handlers.default_view_handler({ path = "/tmp/archive.tar" }))
        H.same({ "tar", "-tvf", "/tmp/archive.tar" }, calls[2])
      end)

      with_view_mocks("text/markdown", "/tmp/readme.md", {}, {
        ["cat /tmp/readme.md"] = { code = 0, stdout = "raw markdown" },
      }, function(calls)
        H.eq("raw markdown", handlers.default_view_handler({ path = "/tmp/readme.md" }))
        H.same({ "cat", "/tmp/readme.md" }, calls[2])
      end)

      with_view_mocks("application/octet-stream", "/tmp/blob.bin", { strings = true }, {
        ["strings /tmp/blob.bin"] = { code = 0, stdout = "binary text" },
      }, function(calls)
        H.eq("binary text", handlers.default_view_handler({ path = "/tmp/blob.bin" }))
        H.same({ "strings", "/tmp/blob.bin" }, calls[2])
      end)

      with_view_mocks("application/octet-stream", "/tmp/blob.bin", {}, {}, function()
        local output = handlers.default_view_handler({ path = "/tmp/blob.bin" })
        H.contains(output, "Unable to view binary file")
        H.contains(output, "application/octet-stream")
      end)
    end,
  },
}
