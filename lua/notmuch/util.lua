local u = {}
local v = vim.api

---Check whether an attachment scratch buffer is empty.
---
---Returns `true` only when every line is blank/whitespace. Callers can use this
---to decide whether a draft should be sent as plain text or as multipart MIME.
---
---@param buf_attach integer Buffer id of the attachment scratch buffer.
---@return boolean empty True when no non-whitespace attachment path is present.
u.empty_attachment_window = function(buf_attach)
  for _, line in ipairs(v.nvim_buf_get_lines(buf_attach, 0, -1, false)) do
    if line:find("%S") then
      return false
    end
  end
  return true
end

---Format a byte count for compact display.
---
---@param bytes integer|nil Size in bytes.
---@return string formatted Human-readable size, or `—` when size is nil/zero.
u.format_size = function(bytes)
  if bytes == 0 or bytes == nil then
    return "—"
  elseif bytes < 1024 then
    return bytes .. "B"
  elseif bytes < 1024 * 1024 then
    return string.format("%.0fK", bytes / 1024)
  elseif bytes < 1024 * 1024 * 1024 then
    return string.format("%.1fM", bytes / (1024 * 1024))
  else
    return string.format("%.1fG", bytes / (1024 * 1024 * 1024))
  end
end

---Check whether a path can be opened for reading.
---
---@param path string File path to test.
---@return boolean exists True when the path can be opened in read mode.
u.file_exists = function(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  else
    return false
  end
end

---Validate that a file path is readable and suitable for attachment.
---
---This checks that the path can be opened for reading and that libuv reports it
---as a regular file, not a directory or special file.
---
---@param path string File path to validate.
---@return boolean valid True when the file is readable and attachable.
---@return string|nil err Error message when validation fails.
u.validate_attachment_file = function(path)
  -- Attempt to open file for reading
  local file, err = io.open(path, "r")

  if not file then
    return false, err
  end

  file:close()

  -- Use vim.uv to check if it's a regular file (not directory/special file)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return false, "Unable to read file metadata"
  end

  if stat.type ~= "file" then
    return false, string.format("Path is a %s, not a regular file", stat.type)
  end

  return true, nil
end

-- Collect all substrings in `s` that match a Lua pattern.
--
-- Despite the historical name, `delim` is passed directly to `string.gmatch` as
-- the match pattern. It should describe the entries to return, not the separator
-- to discard.
--
---@param s string Input string.
---@param delim string Lua pattern used to match returned entries.
---@return string[] entries Substrings matched by `delim`.
u.split = function(s, delim)
  local out = {}
  local i = 1
  for entry in string.gmatch(s, delim) do
    out[i] = entry
    i = i + 1
  end
  return out
end

-- Split a string into fixed-width chunks.
--
---@param s string Input string.
---@param length integer Maximum chunk length.
---@return string[] chunks Chunks of `s`, preserving order.
u.split_length = function(s, length)
  local out = {}

  for i = 1, #s, length do
    out[#out + 1] = s:sub(i, i + length - 1)
  end

  return out
end

-- Prefix a message header line with a visual marker for its reply depth.
--
---@param buf integer Buffer containing the header line.
---@param lineno integer 1-based line number to update.
---@param depth integer Message depth in the thread's reply chain.
--
---@usage
-- -- See u.process_msgs_in_thread() for invocation example
-- indent_depth(buf, lineno, msg.depth)
local indent_depth = function(buf, lineno, depth)
  local line = vim.fn.getline(lineno)
  local s = ""
  for _ = 0, depth - 1 do
    s = "────" .. s
  end
  v.nvim_buf_set_lines(buf, lineno - 1, lineno, true, { s .. line })
end

-- Reformat legacy `notmuch show` text output in-place for the mail buffer.
--
-- This scans a buffer containing raw text output with markers such as
-- `message{`, `header{`, and `message}`. It removes structural noise, inserts
-- fold markers, and indents message headers by reply depth.
--
---@param buf integer Buffer containing legacy `notmuch show` text output.
---@return nil
--
-- Side effects:
-- - Mutates `buf` in-place by adding, removing, and replacing lines.
-- - Adds fold markers `{{{` and `}}}` for message navigation.
-- - Uses synchronous buffer edits and the current window's line APIs.
u.process_msgs_in_thread = function(buf)
  -- Loop over each line in the buffer and clean up the message output format
  local msg = {} -- Table which stores id, depth, file of a message
  local lineno = 1 -- Start from the top of the buffer
  local last = vim.fn.line("$") -- End at the bottom of the buffer

  while lineno <= last do
    -- Store line contents
    local line = vim.fn.getline(lineno)

    -- Message start : Store message details in `msg` and remove the line
    if string.match(line, "^message{") ~= nil then
      msg.id = string.match(line, "id:%S+")
      msg.depth = tonumber(string.match(string.match(line, "depth:%d+"), "%d+"))
      msg.filename = string.match(line, "filename:%C+")
      v.nvim_buf_set_lines(buf, lineno - 1, lineno, true, {})
      lineno = lineno - 1
      last = last - 1 -- Because we removed a line so buffer is shorter

    -- Header fields : Subject, From, To, etc. Indent based on `msg.depth`
    elseif string.match(line, "^header{") ~= nil then
      v.nvim_buf_set_lines(buf, lineno - 1, lineno, true, {}) -- Remove "header("
      indent_depth(buf, lineno, msg.depth)
      line = vim.fn.getline(lineno) -- Add fold start identifier '{{{'
      v.nvim_buf_set_lines(buf, lineno - 1, lineno, true, { line, msg.id .. " {{{" })

    -- Pass over "Subject" field and next header fields
    elseif string.match(line, "^Subject:") ~= nil then
      lineno = lineno + 2
      last = last + 1

    -- Closing header field : Delete
    elseif string.match(line, "^header}") ~= nil then
      v.nvim_buf_set_lines(buf, lineno - 1, lineno, true, { "" })

    -- Closing message field : Replace with folding closing "}}}"
    elseif string.match(line, "^message}") ~= nil then
      v.nvim_buf_set_lines(buf, lineno - 1, lineno, true, { "}}}", "" })
      lineno = lineno + 1
      last = last + 1

    -- Removes extra cruft like "parts", etc.
    elseif string.match(line, "^%a+[{}]") ~= nil then
      v.nvim_buf_set_lines(buf, lineno - 1, lineno, true, {})
      lineno = lineno - 1
      last = last - 1
    end

    -- Increment lineno to inspect the next line, next loop
    lineno = lineno + 1
  end
end

-- Return the notmuch message id for the message under the cursor.
--
-- The search walks upward from the cursor until it finds a fold marker line of
-- the form `id:<message-id> {{{`. If no marker is found, it prints a message and
-- returns nil.
--
---@return string|nil id Message id without the `id:` prefix, or nil when not found.
--
---@usage
-- local id = require('notmuch.util').find_cursor_msg_id()
-- -- Do something with the mail id (e.g. reply, tag, get attachments)
u.find_cursor_msg_id = function()
  local n = v.nvim_win_get_cursor(0)[1] + 1
  local line = nil
  local id = nil
  while n ~= 1 do
    line = vim.fn.getline(n)
    if string.match(line, "^id:%S+ {{{$") ~= nil then
      id = string.match(line, "%S+", 4)
      return id
    end
    n = n - 1
  end

  -- id not found for the cursor location
  print("No ID found. Make sure cursor is located in a message")
  return nil
end

return u

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
