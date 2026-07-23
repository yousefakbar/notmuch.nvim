local m = {}
local u = require("notmuch.util")
local v = vim.api

---Build MIME part descriptors for outgoing attachments.
---
---Each non-empty path is validated as a readable regular file before it is
---included. If any path is invalid, this function raises one aggregated error so
---the caller does not send a partially-valid attachment set.
---
---@param paths string[] List of attachment file paths.
---@return table[] attachments MIME part descriptors for `make_mime_msg()`.
---Raises an error if one or more attachment paths are invalid.
m.create_mime_attachments = function(paths)
  local mimes = {}
  local invalid_files = {} -- Collect all errors for better UX

  for _, path in ipairs(paths) do
    if path ~= "" then
      -- Validate file before adding to attachments
      local valid, err = u.validate_attachment_file(path)

      if not valid then
        -- Collect error for reporting
        table.insert(invalid_files, {
          path = path,
          reason = err or "Unknown error",
        })
      else
        -- File is valid, add to attachments
        table.insert(mimes, {
          file = path,
          type = m.get_mime_type(path),
          attachment = true,
          encoding = "base64",
        })
      end
    end
  end

  -- If any files were invalid, throw error with details
  if #invalid_files > 0 then
    local error_msg = "Failed to attach file(s):\n\n"

    for _, invalid in ipairs(invalid_files) do
      error_msg = error_msg
        .. string.format("  • %s\n    Reason: %s\n\n", invalid.path, invalid.reason)
    end

    error_msg = error_msg .. "Cannot send email with invalid attachments.\n"
    error_msg = error_msg .. "Please verify all attachment paths and try again."

    error(error_msg)
  end

  return mimes
end

-- Extract RFC 5322-style headers and body lines from a message.
--
-- This function consumes a list of message lines. It records header lines in an
-- attributes table keyed by header name, unfolds continuation lines, and stops
-- parsing headers at the first blank line or first non-header line. The returned
-- body table includes the header/body separator when one is present.
--
---@param lines string[] Message lines.
---@return table attributes Header values keyed by header name.
---@return string[] msg Body lines after header parsing.
m.get_msg_attributes = function(lines)
  local attributes = {}
  local msg = {}
  local in_headers = true
  local last_header_key = nil

  for _, line in ipairs(lines) do
    if in_headers then
      -- Check for blank line (header/body separator per RFC 5322)
      if line == "" or line:match("^%s*$") then
        in_headers = false
        table.insert(msg, line)

      -- Check for header continuation (RFC 5322 folding)
      elseif line:match("^[ \t]") and last_header_key then
        attributes[last_header_key] = attributes[last_header_key] .. " " .. line:gsub("^%s+", "")

      -- Check for header line (contains ':')
      elseif line:match(":") then
        local key, value = line:match("^([^:]+):%s*(.*)$")
        if key then
          attributes[key] = value
          last_header_key = key
        end

      -- First non-header line (no ':'), start body
      else
        in_headers = false
        table.insert(msg, line)
      end
    else
      -- Already in body, add all lines
      table.insert(msg, line)
    end
  end

  return attributes, msg
end

m.example_mime = {
  version = "Mime-Version: 1.0",
  type = "multipart/mixed",
  encoding = "8 bit",
  attributes = {
    from = "example@exmple.com", -- results in "from: examle@example.com" in email header
    to = "example@example.com",
    subject = "This is an example",
  },
  mime = {
    {
      type = "multipart/alternative",
      attachment = false,
      mime = {
        {
          file = "/path/to/example.txt",
          type = "text/plain; charset=utf-8",
        },
        {
          file = "/path/to/example.html",
          type = "text/html; charset=utf-8",
        },
      },
    },
    {
      file = "/path/to/example.pdf",
      encoding = "base64",
      attachment = true, -- if not true, then create an inline mime
    },
  },
}

-- Returns the MIME type reported by the `file` command for a path.
--
---@param path string File path to inspect.
---@return string mime_type Trimmed MIME type, for example `text/plain`.
m.get_mime_type = function(path)
  local output = vim.fn.system({ "file", "--brief", "--mime-type", path })
  return vim.fn.trim(output)
end

-- Returns a pseudo-random uppercase ASCII boundary string.
--
---@param length integer Number of characters to generate.
---@return string boundary Pseudo-random boundary string.
m.get_boundary = function(length)
  if length > 0 then
    return m.get_boundary(length - 1) .. string.char(math.random(65, 65 + 25))
  else
    return ""
  end
end

-- Build a MIME message or MIME part as lines.
--
-- `mime_table` may describe a multipart node via its `mime` children, or a leaf
-- node backed by `mime_table.file`. Leaf files are read from disk; base64 parts
-- are encoded and wrapped, while other parts are inserted as plain lines.
--
---@param mime_table table MIME message/part descriptor.
---@return string[] lines MIME-formatted message lines.
m.make_mime_msg = function(mime_table)
  local mime = {}
  if mime_table.mime then
    local boundary = m.get_boundary(32)
    table.insert(mime, "Content-Type: " .. mime_table.type .. ";")
    table.insert(mime, " boundary=" .. boundary)

    if mime_table.encoding then
      table.insert(mime, "Content-Transfer-Encoding: " .. mime_table.encoding)
    else
      table.insert(mime, "Content-Transfer-Encoding: 7bit")
    end

    for key, value in pairs(mime_table.attributes or {}) do
      table.insert(mime, key .. ": " .. value)
    end

    table.insert(mime, "")

    for _, value in ipairs(mime_table.mime) do
      table.insert(mime, "--" .. boundary)
      for _, value2 in ipairs(m.make_mime_msg(value) or {}) do
        table.insert(mime, value2)
      end
    end
    table.insert(mime, "--" .. boundary .. "--")
    table.insert(mime, "")
  else
    if mime_table.type then
      table.insert(mime, "Content-Type: " .. mime_table.type)
    else
      table.insert(mime, "Content-Type: " .. m.get_mime_type(mime_table.file))
    end

    if mime_table.encoding then
      table.insert(mime, "Content-Transfer-Encoding: " .. mime_table.encoding)
    else
      table.insert(mime, "Content-Transfer-Encoding: 7bit")
    end

    local filename = ""
    if mime_table.filename then
      filename = mime_table.filename
    else
      filename = mime_table.file:match("^.+/(.+)$")
    end

    if mime_table.attachment then
      table.insert(mime, [[Content-Disposition: attachment; filename="]] .. filename .. [["]])
    else
      table.insert(mime, "Content-Disposition: inline")
    end

    -- Open file (should never fail - validation happens in create_mime_attachments)
    local file, err = io.open(mime_table.file, "r")

    -- Defensive check: this should never happen if validation worked correctly
    if not file then
      error(
        string.format(
          "INTERNAL ERROR: Failed to open validated attachment file: %s\nReason: %s\n"
            .. "This should not happen - please report this bug.",
          mime_table.file,
          err or "Unknown error"
        )
      )
    end

    table.insert(mime, "")
    local content = {}
    local base64 = require("notmuch.base64")

    if mime_table.encoding == "base64" then
      content = base64.encode(file:read("*a"))

      -- RFC 2045 defines that the maximum line length for encoded base64 is 76 chars
      local split = u.split_length(content, 76)
      for _, value in ipairs(split) do
        table.insert(mime, value)
      end
    else
      for line in file:lines() do
        table.insert(mime, line)
      end
    end

    file:close() -- Close file handle
    table.insert(mime, "")
  end
  return mime
end

-- a temporary testing function
-- writes the final mime email to the buffer
-- so you can see what the result looks like
m.mime_test = function()
  local lines = m.make_mime_msg(m.example_mime)

  local buf = v.nvim_create_buf(true, false)
  v.nvim_win_set_buf(0, buf)
  v.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

return m
