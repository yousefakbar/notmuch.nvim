local P = {}

--------------------------------------------------------------------------------
-- MODULE IMPORTS
--------------------------------------------------------------------------------

local v = vim.api
local extractor = require("notmuch.attach.incoming.extractor")
local util = require("notmuch.util")
local thread = require("notmuch.thread")

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
--------------------------------------------------------------------------------

local function show_github_patch(link)
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, link)
  v.nvim_win_set_buf(0, buf)
  v.nvim_command("silent 0read! curl -Ls " .. link)
  v.nvim_win_set_cursor(0, { 1, 0 })
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "gitsendemail"
  vim.bo.modifiable = false
end

--- Formats a list of MIME parts into display lines for the attachment buffer.
--
-- Creates a table of formatted strings with aligned columns showing:
-- - Disposition indicator: "I" for inline parts, "A" for attachments
-- - Part ID: The notmuch part number
-- - Filename: The attachment name, or "body (<content-type>)" for inline parts
-- - Size: Human-readable size (e.g., "75K", "1.5M")
--
-- The first line is a header row with column labels.
--
-- Column alignment:
-- - Disposition: 2 chars, left-aligned
-- - ID: 5 chars, left-aligned
-- - File: 45 chars, left-aligned
-- - Size: 6 chars, right-aligned
--
---@param parts_list MimePart[] Array of MIME part information tables
---@return string[] Array of formatted display lines (including header)
local function format_part_line(parts_list)
  local output = { string.format("%-2s %-5s %-45s %6s", "?", "ID", "File", "Size") }

  for _, part in ipairs(parts_list) do
    -- Determine disposition indicator
    local indicator = "A"
    if part.disposition == "inline" then
      indicator = "I"
    end

    -- Choose display name
    local filename = part.filename
    if filename == "" then
      filename = "body (" .. part.content_type .. ")"
    end

    -- Format size to human-readable
    local size = util.format_size(part.size)

    -- Build the display string with aligned columns
    table.insert(output, string.format("%-2s %-5s %-45s %6s", indicator, part.id, filename, size))
  end

  return output
end

--- MIME part information table
---@class MimePart
---@field id number The notmuch part ID (e.g., 2, 3, 4)
---@field content_type string The MIME content type (e.g., "text/html", "application/pdf")
---@field filename string The attachment filename, or empty string if none
---@field disposition string Either "inline" or "attachment"
---@field size number Size in bytes

--- Recursively parses a MIME tree from notmuch JSON output and collects openable parts.
--
-- This function traverses the MIME structure recursively, filtering out multipart/*
-- container nodes and collecting only leaf nodes (actual openable content) into the
-- parts_list table.
--
-- Multipart containers (multipart/mixed, multipart/alternative, multipart/related, etc.)
-- are skipped, but their children are recursively processed.
--
-- The parts_list is modified in place - collected parts are appended as MimePart tables.
--
---@param part table A MIME part object from notmuch JSON (must have 'content-type' field)
---@param parts_list MimePart[] Accumulator array to collect openable parts (modified in place)
local function parse_mime_tree(part, parts_list)
  local content_type = part["content-type"]

  -- Check if part is a multipart container
  if content_type:match("^multipart/") then
    -- Don't add to the parts_list, but add its children (recursively)
    if part.content then
      for _, child_part in ipairs(part.content) do
        parse_mime_tree(child_part, parts_list)
      end
    end
    return
  end

  -- Otherwise, leaf node goes into the parts_list
  local disposition = part["content-disposition"] or "inline"
  if disposition == "inline" and not content_type:match("^text/") then
    disposition = "attachment"
  end

  -- Formulate part and add to parts_list
  table.insert(parts_list, {
    id = part.id,
    content_type = content_type,
    filename = part.filename or "",
    disposition = disposition,
    size = part["content-length"] or 0,
  })
end

--- Retrieves the MIME part at the current cursor position in an attachment buffer.
--
-- This function maps the cursor line number to the corresponding part in the
-- buffer-local 'mime_parts_list' variable. It accounts for the 3-line header
-- offset (Hints line, blank line, and column header line).
--
-- Returns nil if:
-- - No parts list exists (not in an attachment buffer)
-- - Cursor is on a header line (lines 1-3)
-- - Cursor is beyond the last part
--
-- Used by save/open/view attachment functions to determine which part to operate on.
--
---@return MimePart|nil Part The MIME part at cursor, or nil if invalid position
local function get_part_at_cursor()
  -- Get the buffer-local MIME parts list variable
  local bufnr = v.nvim_get_current_buf()
  local ok, parts_list = pcall(v.nvim_buf_get_var, bufnr, "mime_parts_list")

  -- If no attachments/parts, return gracefully
  if not ok or not parts_list then
    return nil
  end

  -- Get part index based on line number
  local cursor_line = v.nvim_win_get_cursor(0)[1]

  -- Offset by -3 lines for static text (Hints, blank, header)
  local parts_index = cursor_line - 3

  -- Validate in case out-of-bounds
  if parts_index < 1 or parts_index > #parts_list then
    return nil
  end

  -- We can map line number to index in 'mime_parts_list'
  return parts_list[parts_index]
end

--------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
--------------------------------------------------------------------------------

--- Opens an attachment listing buffer for the email message at the cursor position.
---
--- This function creates a new split window below the current window displaying all
--- MIME parts found in the email message. The listing shows:
--- - Inline parts (I): text/plain, text/html body content
--- - Attachments (A): files attached to the email
---
--- The buffer is named 'id:<message-id>' and has filetype 'notmuch-attach'.
--- Buffer-local variable 'mime_parts_list' contains the structured part data.
---
--- Multipart/* containers are automatically filtered out and only leaf nodes
--- (openable parts) are displayed with their notmuch part IDs for direct access.
function P.get_attachments_from_cursor_msg()
  -- Get msg ID from cursor location and validate
  local id = thread.get_current_message_id()
  if id == nil then
    return nil
  end

  -- If attachment buffer already exists, notify and return
  local bufnr = vim.fn.bufnr("id:" .. id)
  if bufnr ~= -1 then
    -- TODO: why warn when we can just open the existing buffer again?
    vim.notify(
      "Attachment list for this msg is already open in buffer: " .. bufnr,
      vim.log.levels.WARN
    )
    return nil
  end

  -- Create new attachment listing buffer (`notmuch-attach`)
  v.nvim_command("belowright 8new")
  v.nvim_buf_set_name(0, "id:" .. id)
  vim.bo.buftype = "nofile"

  -- Get all MIME parts from `msg` in JSON format
  local result = vim.json.decode(
    vim.fn.system("notmuch show --exclude=false --part=0 --format=json 'id:" .. id .. "'")
  )
  local parts_list = {}
  parse_mime_tree(result["body"][1], parts_list)
  local lines = format_part_line(parts_list)

  -- Save MIME parts list to buffer local variable
  v.nvim_buf_set_var(0, "mime_parts_list", parts_list)

  -- Add hints and output, set filetype, and switch off modifiable
  v.nvim_buf_set_lines(0, 0, 0, true, { "Hints: v: View | o: Open | s: Save | q: Close", "" })
  v.nvim_buf_set_lines(0, -2, -1, true, lines)
  v.nvim_win_set_cursor(0, { 1, 0 })
  vim.bo.filetype = "notmuch-attach"
  vim.bo.modifiable = false
end

--- Saves the MIME part at cursor to disk.
--
-- When prompt_user is true, prompts for save location with interactive input.
-- Supports directory-only input (will append original filename).
-- Validates directory existence/writability and confirms overwrites.
--
---@param savedir string|nil Directory to save to (defaults to cwd when prompting, '.' otherwise)
---@param prompt_user boolean Whether to prompt for save location
---@return string|nil filepath Path to saved file, or nil if cancelled/failed
function P.save_attachment_part(savedir, prompt_user)
  -- Get part details from current cursor location
  local part = get_part_at_cursor()

  -- If not a valid part, return early
  if not part then
    return nil
  end

  -- Extract message ID from buffer name
  local id = string.match(v.nvim_buf_get_name(0), "id:%C+")

  -- Use actual filename if available, otherwise generate from content-type
  local filename = part.filename:gsub("/", "-")
  if filename == "" then
    local ext = string.match(part.content_type, "%w+/(%w+)")
    if ext == "plain" then
      ext = "txt"
    end
    filename = "notmuch." .. ext
  end

  -- Set directory in which to save the attachment part
  -- local dir = savedir or '.'

  local filepath

  -- If prompt user is true, have the user select and confirm the save location
  if prompt_user then
    -- Determine default directory (savedir or current directory)
    local default_dir = savedir or vim.fn.getcwd()
    local default_path = default_dir .. "/" .. filename

    -- Prompt user for save location
    filepath = vim.fn.input("Save file: ", default_path, "file")
    vim.cmd("redraw")

    -- If user cancels (ESC or empty input), return nil
    if filepath == "" then
      vim.notify("Save cancelled", vim.log.levels.INFO)
      return nil
    end

    -- Expand path (handles ~ and environment variables)
    filepath = vim.fn.expand(filepath)

    -- If user provided a directory, append the filename
    if vim.fn.isdirectory(filepath) == 1 then
      -- Remove trailing slash if present, then add filename
      filepath = filepath:gsub("/$", "") .. "/" .. filename
    end

    -- Extract directory from filepath
    local dir = vim.fn.fnamemodify(filepath, ":h")

    -- Check if directory exists
    if vim.fn.isdirectory(dir) == 0 then
      vim.notify("Directory does not exist", vim.log.levels.ERROR)
      return nil
    end

    -- Check if directory is writable
    if vim.fn.filewritable(dir) ~= 2 then
      vim.notify("Directory is not writable", vim.log.levels.ERROR)
      return nil
    end

    -- Check if file already exists - If so, prompt for confirmation
    if vim.fn.filereadable(filepath) == 1 then
      local confirm = vim.fn.confirm("File exists. Overwrite?", "&Yes\n&No", 2)
      vim.cmd("redraw")
      if confirm ~= 1 then
        vim.notify("Save cancelled", vim.log.levels.INFO)
        return nil
      end
    end
  else
    -- No prompt -- This is used by open/view attachment
    local dir = savedir or "."
    filepath = dir .. "/" .. filename
  end

  local saved_path, err = extractor.save_to_path(id, part, filepath)
  if not saved_path then
    vim.notify(err or "Failed to save attachment", vim.log.levels.ERROR)
    return nil
  end

  print("Saved to: " .. saved_path)
  return saved_path
end

--- Opens the MIME part at cursor with the incoming attachment opener.
--
-- Extracts the attachment to the configured incoming attachment cache, then
-- delegates to the rule-based opener.
--
---@return boolean|nil ok True when opened, or nil on failure/invalid cursor.
function P.open_attachment_part()
  local part = get_part_at_cursor()
  if not part then
    return nil
  end

  local id = string.match(v.nvim_buf_get_name(0), "id:%C+")
  local ok = require("notmuch.attach.incoming").open_part(part, id)
  return ok or nil
end

--- Views the MIME part at cursor in a floating window.
--
-- Extracts the attachment to the configured incoming attachment cache, converts
-- it with the rule-based viewer, and renders the result in a floating window.
-- Press 'q' to close the window.
--
---@return table|nil rendered Rendered preview handles, or nil on failure/invalid cursor.
function P.view_attachment_part()
  local part = get_part_at_cursor()
  if not part then
    return nil
  end

  local id = string.match(v.nvim_buf_get_name(0), "id:%C+")
  local rendered = require("notmuch.attach.incoming").view_part(part, id)
  return rendered
end

function P.get_urls_from_cursor_msg()
  if vim.fn.exists(":YTerm") == 0 then
    print("Can't launch URL selector (:YTerm command not found)")
    return nil
  end
  local id = thread.get_current_message_id()
  if id == nil then
    return nil
  end
  v.nvim_command('YTerm "notmuch show id:' .. id .. ' | urlextract"')
end

function P.follow_github_patch(line)
  -- https://github.com/neomutt/neomutt/pull/2774.patch
  local link = string.match(line, "http[s]://github%.com/.+/.+/pull/%d+%.patch")
  if link == nil then
    return nil
  end
  local bufno = vim.fn.bufnr(link)
  if bufno ~= -1 then
    v.nvim_win_set_buf(0, bufno)
  else
    show_github_patch(link)
  end
end

return P
