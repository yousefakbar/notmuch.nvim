--- notmuch.attach.scratch -- Scratch buffer UI for attachment management
---
--- This module contains the UI logic for scratch buffer management of
--- attachment filepaths, and the wiring to underlying state in the state
--- module.
---
--- While drafting, the user will have access to a linked scratch buffer for
--- listing attachment filepaths. This module synchronizes those buffer lines to
--- the canonical state (sidecar JSON) and the buffer-local variable which
--- mirrors it. Transactions to the attachment state are done through the state
--- module, not directly here.

---@class notmuch.attach.ScratchOpenOpts

local S = {}

-- -----------------------------------------------------------------------------
-- MODULE IMPORTS
-- -----------------------------------------------------------------------------

local v = vim.api
local state = require("notmuch.attach.state")

-- -----------------------------------------------------------------------------
-- PRIVATE HELPERS
-- -----------------------------------------------------------------------------

local function normalize_buf(buf)
  -- If 0 or no buf passed, use current buffer
  if buf == nil or buf == 0 then
    return v.nvim_get_current_buf()
  end

  -- Verify `buf` is a valid buffer
  if not v.nvim_buf_is_valid(buf) then
    error("Invalid buffer: " .. tostring(buf))
  end

  return buf
end

local function get_linked_scratch_buffer(draft_buf)
  -- Get linked scratch buffer from the buffer-local variable in the parent buf
  local ok, scratch_buf = pcall(v.nvim_buf_get_var, draft_buf, "notmuch_attachment_scratch_buf")
  if not ok or type(scratch_buf) ~= "number" then
    return nil
  end

  -- Validate buffer is valid
  if not v.nvim_buf_is_valid(scratch_buf) then
    return nil
  end

  return scratch_buf
end

local function get_parent_draft_buf(scratch_buf)
  local ok, draft_buf = pcall(v.nvim_buf_get_var, scratch_buf, "notmuch_parent_draft_buf")
  if not ok or type(draft_buf) ~= "number" then
    return nil
  end

  if not v.nvim_buf_is_valid(draft_buf) then
    return nil
  end

  return draft_buf
end

local function set_syncing(scratch_buf, value)
  v.nvim_buf_set_var(scratch_buf, "notmuch_attachment_syncing", value)
end

local function is_syncing(scratch_buf)
  local ok, syncing = pcall(v.nvim_buf_get_var, scratch_buf, "notmuch_attachment_syncing")
  return ok and syncing == true
end

local function setup_autocmds(scratch_buf)
  -- Create augroup for the specific scratch buffer, and clear any existing
  local group = v.nvim_create_augroup("notmuch_attach_scratch_" .. scratch_buf, {
    clear = true,
  })

  -- Create syncing autocommands on TextChanged, [TextChangedI], BufLeave events
  v.nvim_create_autocmd({ "TextChanged", "BufLeave" }, { -- 'TextChangedI' optional later
    group = group,
    buffer = scratch_buf,
    callback = function()
      S.sync_from_scratch(scratch_buf)
    end,
  })

  -- Create unlink parent draft_buf autocommand on scratch buffer closure
  v.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = scratch_buf,
    callback = function()
      local draft_buf = get_parent_draft_buf(scratch_buf)
      if draft_buf and v.nvim_buf_is_valid(draft_buf) then
        pcall(v.nvim_buf_del_var, draft_buf, "notmuch_attachment_scratch_buf")
      end
    end,
  })
end

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

--- Open or focus the attachment scratch buffer for a draft buffer.
---
--- If a linked scratch buffer already exists, it is shown in a split and
--- refreshed. Otherwise, a new scratch buffer is created and linked to the
--- draft buffer.
---
---@param draft_buf integer? Draft buffer. Defaults to the current buffer.
---@param opts? notmuch.attach.ScratchOpenOpts Reserved for future options.
---@return integer scratch_buf Buffer handle of the scratch buffer.
function S.open(draft_buf, opts)
  draft_buf = normalize_buf(draft_buf)
  opts = opts or {}

  -- If scratch buffer already exists, open in split and refresh
  local existing = get_linked_scratch_buffer(draft_buf)
  if existing then
    -- Show existing buffer somehow
    vim.cmd("belowright 8split")
    v.nvim_win_set_buf(0, existing)
    S.refresh(draft_buf)
    return existing
  end

  -- Not existing, so create and initialize the linked buffer
  vim.cmd("belowright 8new")
  local scratch_buf = v.nvim_get_current_buf()

  -- Set scratch buffer options
  v.nvim_buf_set_name(scratch_buf, "notmuch-attachments:" .. draft_buf)
  vim.bo[scratch_buf].buftype = "nofile"
  vim.bo[scratch_buf].bufhidden = "hide"
  vim.bo[scratch_buf].swapfile = false
  vim.bo[scratch_buf].filetype = "notmuch-attach-draft"

  -- Link scratch and draft buffer and initialize buffer-local variables
  v.nvim_buf_set_var(draft_buf, "notmuch_attachment_scratch_buf", scratch_buf)
  v.nvim_buf_set_var(scratch_buf, "notmuch_parent_draft_buf", draft_buf)
  v.nvim_buf_set_var(scratch_buf, "notmuch_attachment_syncing", false)

  S.refresh(draft_buf)
  setup_autocmds(scratch_buf)

  return scratch_buf
end

--- Refresh a linked scratch buffer from canonical attachment state.
---
---@param draft_buf integer? Draft buffer. Defaults to the current buffer.
---@return boolean ok False when no linked scratch buffer exists.
function S.refresh(draft_buf)
  draft_buf = normalize_buf(draft_buf)

  local scratch_buf = get_linked_scratch_buffer(draft_buf)
  if not scratch_buf then
    return false
  end

  local attachments = state.get(draft_buf)

  set_syncing(scratch_buf, true)

  local was_modifiable = vim.bo[scratch_buf].modifiable
  vim.bo[scratch_buf].modifiable = true
  v.nvim_buf_set_lines(scratch_buf, 0, -1, false, attachments)
  vim.bo[scratch_buf].modifiable = was_modifiable

  set_syncing(scratch_buf, false)

  return true
end

--- Synchronize canonical attachment state from scratch buffer lines.
---
---@param scratch_buf integer? Scratch buffer. Defaults to the current buffer.
---@return boolean ok
---@return string? err Error message when synchronization fails.
function S.sync_from_scratch(scratch_buf)
  -- Normalize scratch buffer input and verify it is not being modified
  scratch_buf = normalize_buf(scratch_buf)
  if is_syncing(scratch_buf) then
    return true
  end

  -- Get linked parent draft buffer
  local draft_buf = get_parent_draft_buf(scratch_buf)
  if not draft_buf then
    return false, "No parent draft buffer"
  end

  -- Get list of attachments (table of lines from scratch_buf)
  local lines = v.nvim_buf_get_lines(scratch_buf, 0, -1, false)

  -- Persist/sync to the state (sidecar JSON) -- no refresh to buffer
  local ok, err = state.set(draft_buf, lines, {
    persist = true,
    refresh_scratch = false,
  })

  if not ok then
    return false, err
  end

  return true
end

--- Synchronize any open attachment scratch buffer for a draft buffer.
---
--- This is intended to run before sending or persisting the draft so edits made
--- directly in the scratch buffer are not lost.
---
---@param draft_buf integer? Draft buffer. Defaults to the current buffer.
---@return boolean ok
---@return string? err Error message when synchronization fails.
function S.sync_open(draft_buf)
  -- Normalize input draft_buf
  draft_buf = normalize_buf(draft_buf)

  -- Get scratch buffer linked to the input draft_buf
  local scratch_buf = get_linked_scratch_buffer(draft_buf)
  if not scratch_buf then
    return true
  end

  -- This will sync the state before sending the email, etc.
  return S.sync_from_scratch(scratch_buf)
end

return S
