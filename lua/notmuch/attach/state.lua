--- notmuch.attach.state -- Canonical attachments state layer
---
--- This module should be the canonical runtime state layer for outgoing draft
--- attachments. It should not know about windows/keymaps too much; that belongs
--- to scratch.lua and commands.lua.
---
--- The purpose of this module is to sync and manage the draft attachments:
---
--- 1. Canonical sidecar JSON attachments metadata
--- 2. Runtime state with buffer-local variable `vim.b[buf].notmuch_attachments`

---@alias notmuch.AttachmentPath string

---@class notmuch.attach.SetOpts
---@field persist? boolean Whether to persist to the draft JSON sidecar. Defaults to true.
---@field refresh_scratch? boolean Whether to refresh the linked scratch buffer. Defaults to true.

local S = {}

-- -----------------------------------------------------------------------------
-- MODULE IMPORTS
-- -----------------------------------------------------------------------------

local v = vim.api
local util = require("notmuch.util")
local draft = require("notmuch.draft")

-- -----------------------------------------------------------------------------
-- PRIVATE HELPERS
-- -----------------------------------------------------------------------------

local function trim(str)
  return str:match("^%s*(.-)%s*$")
end

local function copy_list(list)
  local copy = {}
  for _, item in ipairs(list) do
    table.insert(copy, item)
  end
  return copy
end

local function normalize_buf(buf)
  if buf == nil or buf == 0 then
    return v.nvim_get_current_buf()
  end

  if not v.nvim_buf_is_valid(buf) then
    error("Invalid buffer: " .. tostring(buf))
  end

  return buf
end

local function normalize_path(path)
  path = trim(tostring(path or ""))
  if path == "" then
    return ""
  end

  path = vim.fn.expand(path)
  path = vim.fn.fnamemodify(path, ":p")

  return path
end

local function normalize_attachments(attachments)
  local normalized = {}
  local seen = {}

  if type(attachments) ~= "table" then
    return normalized
  end

  for _, path in ipairs(attachments) do
    if type(path) == "string" then
      local filepath = normalize_path(path)

      if filepath ~= "" and not seen[filepath] then
        seen[filepath] = true
        table.insert(normalized, filepath)
      end
    end
  end

  return normalized
end

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

--- Get attachments for a draft buffer.
---
--- Returns a copy of the buffer-local attachment list so callers cannot mutate
--- the canonical runtime state directly.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@return notmuch.AttachmentPath[] attachments
function S.get(buf)
  -- Validate/normalize buffer
  buf = normalize_buf(buf)

  -- Fetch attachments from the state mirror (buffer-local variable)
  local ok, attachments = pcall(v.nvim_buf_get_var, buf, "notmuch_attachments")
  if not ok or type(attachments) ~= "table" then
    return {}
  end

  return copy_list(attachments)
end

--- Replace the attachment list for a draft buffer.
---
--- Paths are expanded to absolute paths, empty entries are removed, and
--- duplicates are discarded. By default, the result is persisted to the draft
--- sidecar metadata and any linked scratch buffer is refreshed.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@param attachments notmuch.AttachmentPath[] Attachment paths to store.
---@param opts? notmuch.attach.SetOpts Persistence/refresh options.
---@return boolean ok
function S.set(buf, attachments, opts)
  -- Validate/normalize arguments
  buf = normalize_buf(buf)
  opts = opts or {}
  local normalized = normalize_attachments(attachments)

  -- Save normalized `attachments` to buffer-local variable (mirror of state)
  v.nvim_buf_set_var(buf, "notmuch_attachments", normalized)

  -- If `persist` option enabled, save changes to JSON sidecar (canonical state)
  if opts.persist ~= false then
    local ok = S.persist(buf)
    if not ok then
      return false
    end
  end

  -- Optionally refresh the scratch buffer if enabled in `opts`
  if opts.refresh_scratch ~= false then
    local ok_scratch, scratch = pcall(require, "notmuch.attach.scratch")
    if ok_scratch and scratch.refresh then
      scratch.refresh(buf)
    end
  end

  return true
end

--- Add an attachment to a draft buffer.
---
--- The path is normalized and validated before being appended. Duplicate paths
--- are rejected.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@param path string Attachment path.
---@param opts? notmuch.attach.SetOpts Persistence/refresh options.
---@return boolean ok
---@return string path_or_err Normalized path on success, error message on failure.
---@return integer? count Attachment count on success.
function S.add(buf, path, opts)
  -- Validate/normalize buffer
  buf = normalize_buf(buf)

  -- Normalize attachment path
  local filepath = normalize_path(path)
  if filepath == "" then
    return false, "Attachment path is empty"
  end

  -- Validate attachment path
  local valid, err = util.validate_attachment_file(filepath)
  if not valid then
    return false, err
  end

  -- Get current attachments state
  local attachments = S.get(buf)

  -- Check if filepath is already attached in state, return accordingly
  for _, existing in ipairs(attachments) do
    if existing == filepath then
      return false, "Already attached: " .. filepath
    end
  end

  -- Since filepath is not alreaady in attachments, add it here
  table.insert(attachments, filepath)

  -- Set/persist to the state
  local ok = S.set(buf, attachments, opts)
  if not ok then
    return false, "Failed to persist attachment metadata"
  end

  return true, filepath, #attachments
end

--- Remove an attachment from a draft buffer.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@param path string Attachment path.
---@param opts? notmuch.attach.SetOpts Persistence/refresh options.
---@return boolean ok
---@return string path_or_err Normalized path on success, error message on failure.
---@return integer? count Attachment count on success.
function S.remove(buf, path, opts)
  -- Validate/normalize buffer
  buf = normalize_buf(buf)

  -- Get existing attachments from the normalized path
  local filepath = normalize_path(path)
  local attachments = S.get(buf)

  -- Find the `path` attachment from the current attachments state
  local found_index
  for i, existing in ipairs(attachments) do
    if existing == filepath then
      found_index = i
      break
    end
  end

  -- If attachment is not already in attachements state, return early
  if not found_index then
    return false, "File not in attachments: " .. filepath
  end

  -- Remove found attachment from the list
  table.remove(attachments, found_index)

  -- Persist/save to state
  local ok = S.set(buf, attachments, opts)
  if not ok then
    return false, "Failed to persist attachment metadata"
  end

  return true, filepath, #attachments
end

--- Persist the current buffer-local attachment state to the draft sidecar JSON.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@return boolean ok
function S.persist(buf)
  -- Validate/normalize buffer
  buf = normalize_buf(buf)
  return draft.save_buffer_attachments(buf, S.get(buf))
end

return S
