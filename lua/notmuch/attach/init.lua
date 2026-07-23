--- Public attachment API for notmuch draft buffers.
---
--- This module re-exports the attachment state, scratch UI, and command helpers
--- used by draft buffers. Prefer requiring this module from external call sites
--- instead of depending on the lower-level implementation modules directly.

---@class notmuch.attach.SetupDraftBufferOpts
---@field open_scratch? boolean Open the attachment scratch buffer after setup.

local A = {}

-- -----------------------------------------------------------------------------
-- MODULE IMPORTS
-- -----------------------------------------------------------------------------

local state = require("notmuch.attach.state")
local scratch = require("notmuch.attach.scratch")
local commands = require("notmuch.attach.commands")

-- -----------------------------------------------------------------------------
-- Draft attachment state
-- -----------------------------------------------------------------------------

A.get = state.get
A.set = state.set
A.add = state.add
A.remove = state.remove
A.persist = state.persist

-- -----------------------------------------------------------------------------
-- Scratch buffer UI
-- -----------------------------------------------------------------------------

A.open_scratch = scratch.open
A.refresh_scratch = scratch.refresh
A.sync_from_scratch = scratch.sync_from_scratch
A.sync_open_scratch = scratch.sync_open

-- -----------------------------------------------------------------------------
-- Command UI
-- -----------------------------------------------------------------------------

A.setup_buffer_commands = commands.setup_buffer

-- Optional: expose handlers too for testing and custom integrations
A.attach_handler = commands.attach_handler
A.remove_handler = commands.remove_handler
A.list_handler = commands.list_handler
A.open_handler = commands.open_handler
A.remove_completion = commands.remove_completion

-- -----------------------------------------------------------------------------
-- Helper functions
-- -----------------------------------------------------------------------------

--- Initialize attachment state and commands for a draft buffer.
---
---@param buf integer Draft buffer.
---@param attachments? notmuch.AttachmentPath[] Initial attachment paths.
---@param opts? notmuch.attach.SetupDraftBufferOpts
---@return boolean ok
function A.setup_draft_buffer(buf, attachments, opts)
  opts = opts or {}

  local ok = state.set(buf, attachments or {}, {
    persist = false,
    refresh_scratch = false,
  })

  if not ok then
    return false
  end

  commands.setup_buffer(buf)

  if opts.open_scratch then
    scratch.open(buf)
  end

  return true
end

--- Synchronize attachment UI state and persist attachments before sending.
---
---@param buf integer Draft buffer.
---@return notmuch.AttachmentPath[]? attachments Normalized attachments, or nil if persistence failed.
function A.prepare_send(buf)
  scratch.sync_open(buf)

  local ok = state.persist(buf)
  if not ok then
    return nil
  end

  return state.get(buf)
end

return A
