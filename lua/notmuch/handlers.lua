local H = {}

--- Default handler for opening attachments externally
---@param attachment table Table with 'path' field containing file path
H.default_open_handler = function(attachment)
  local path = attachment.path

  -- If `nvim` version >=0.10.0, use `vim.ui.open()`
  if vim.ui and vim.ui.open then
    local _, err = vim.ui.open(path)
    if err then
      vim.notify("notmuch.nvim: failed to open attachment: " .. tostring(err), vim.log.levels.ERROR)
    end
    return
  end

  -- Detect OS and choose appropriate command
  local open_cmd
  local sysname = vim.uv.os_uname()

  if sysname.sysname == "Darwin" then
    open_cmd = "open"
  elseif sysname.sysname == "Linux" then
    open_cmd = "xdg-open"
  elseif sysname.sysname:match("Windows") then
    open_cmd = "start"
  else
    open_cmd = "xdg-open" -- fallback
  end

  -- Execute
  local ok, err = pcall(vim.system, { open_cmd, path }, { detach = true })
  if not ok then
    vim.notify("notmuch.nvim: failed to open attachment: " .. tostring(err), vim.log.levels.ERROR)
  end
end

--- Default handler for viewing attachments in the floating window viewer
---@param attachment table Table with 'path' field containing file path
---@return string Text content to display in floating window
H.default_view_handler = function(attachment)
  local path = attachment.path -- Already expanded, careful to escape

  -- Helper function to "try" commands in order until one works
  local function try_commands(commands)
    for _, cmd in ipairs(commands) do
      -- Check if the tool exists
      if vim.fn.executable(cmd.tool) == 1 then
        local output
        local success
        local command = cmd.command(path)
        if type(command) == "table" then
          local obj = vim.system(command):wait()
          output = obj.stdout
          success = (obj.code == 0)
        else
          output = vim.fn.system(command)
          success = (vim.v.shell_error == 0)
        end

        if success then
          return output
        end
      end
    end
    return nil
  end

  -- Detect file type
  local filetype = vim.fn.system({ "file", "--mime-type", "-b", path }):gsub("%s+$", "")
  local ext = path:match("%.([^%.]+)$") or ""

  -- HTML files (most common)
  if filetype:match("^text/html$") or ext:match("^html?$") then
    return try_commands({
      {
        tool = "w3m",
        command = function(p)
          return { "w3m", "-T", "text/html", "-dump", p }
        end,
      },
      {
        tool = "lynx",
        command = function(p)
          return { "lynx", "-dump", "-nolist", p }
        end,
      },
      {
        tool = "elinks",
        command = function(p)
          return { "elinks", "-dump", "-no-references", p }
        end,
      },
    }) or "HTML file (install w3m, lynx, or elinks to view)"
  end

  -- PDF files
  if filetype:match("^application/pdf$") or ext == "pdf" then
    return try_commands({
      {
        tool = "pdftotext",
        command = function(p)
          return { "pdftotext", "-layout", p, "-" }
        end,
      },
      {
        tool = "mutool",
        command = function(p)
          return { "mutool", "draw", "-F", "txt", p }
        end,
      },
    }) or "PDF file (install pdftotext or mutool to view)"
  end

  -- Images
  if filetype:match("^image/") then
    return try_commands({
      {
        tool = "chafa",
        command = function(p)
          return { "chafa", "--size", "80x40", p }
        end,
      },
      {
        tool = "catimg",
        command = function(p)
          return { "catimg", "-w", "80", p }
        end,
      },
      {
        tool = "viu",
        command = function(p)
          return { "viu", "-w", "80", p }
        end,
      },
      {
        tool = "exiftool",
        command = function(p)
          return { "exiftool", p }
        end,
      },
      {
        tool = "identify",
        command = function(p)
          return { "identify", "-verbose", p }
        end,
      },
    }) or "Image file (install chafa, viu, or exiftool to view)"
  end

  -- Office documents (docx, xlsx, pptx)
  if filetype:match("officedocument") or ext:match("^(docx?|xlsx?|pptx?)$") then
    return try_commands({
      {
        tool = "pandoc",
        command = function(p)
          return { "pandoc", "-t", "plain", p }
        end,
      },
      {
        tool = "docx2txt",
        command = function(p)
          return { "docx2txt", p, "-" }
        end,
      },
    }) or "Office document (install pandoc or docx2txt to view)"
  end

  -- Markdown
  if filetype:match("^text/markdown$") or ext:match("^md$") then
    return try_commands({
      {
        tool = "pandoc",
        command = function(p)
          return { "pandoc", "-t", "plain", p }
        end,
      },
      {
        tool = "mdcat",
        command = function(p)
          return { "mdcat", p }
        end,
      },
    }) or vim.fn.system({ "cat", path })
  end

  -- Archives (zip, tar, tar.gz, etc.)
  if filetype:match("zip") or ext == "zip" then
    return vim.fn.system({ "unzip", "-l", path })
  end
  if filetype:match("tar") or ext:match("^tar%.?") then
    return vim.fn.system({ "tar", "-tvf", path })
  end

  -- Plain text (fallback for text/*)
  if filetype:match("^text/") then
    return vim.fn.system({ "cat", path })
  end

  return try_commands({
    {
      tool = "strings",
      command = function(p)
        return { "strings", p }
      end,
    },
  }) or string.format("Unable to view binary file\nType: %s\nPath: %s", filetype, path)
end

return H
