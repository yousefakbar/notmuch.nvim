--- notmuch.attach.commands -- Buffer-local commands for draft attachments
---
--- This module provides the command-layer UI for managing outgoing draft
--- attachments. It defines handlers and registration helpers for commands like
--- `:Attach`, `:AttachRemove`, `:AttachList`, and `:AttachOpen`.
---
--- The commands do not mutate attachment state directly. Instead, they delegate
--- all state changes to `notmuch.attach.state` and scratch-buffer interactions
--- to `notmuch.attach.scratch`, keeping the sidecar JSON metadata,
--- `b:notmuch_attachments`, and scratch buffer synchronized through the shared
--- attachment architecture.

local C = {}

-- -----------------------------------------------------------------------------
-- MODULE IMPORTS
-- -----------------------------------------------------------------------------

local v = vim.api
local state = require("notmuch.attach.state")
local scratch = require("notmuch.attach.scratch")

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

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

--- Create a handler for the `:Attach` buffer-local command.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@return fun(opts: vim.api.keyset.create_user_command.command_args)
function C.attach_handler(buf)
  buf = normalize_buf(buf)

  return function(opts)
    local ok, filepath_or_err, count = state.add(buf, opts.args)

    if not ok then
      local is_duplicate = vim.startswith(filepath_or_err, "Already attached:")
      local level = is_duplicate and vim.log.levels.WARN or vim.log.levels.ERROR
      local msg = is_duplicate and filepath_or_err
        or ("Cannot attach " .. opts.args .. "\n" .. filepath_or_err)
      vim.notify(msg, level)
      return
    end

    vim.notify(
      string.format("Attached: %s (%d total)", filepath_or_err, count),
      vim.log.levels.INFO
    )
  end
end

--- Create a handler for the `:AttachRemove` buffer-local command.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@return fun(opts: vim.api.keyset.create_user_command.command_args)
function C.remove_handler(buf)
  buf = normalize_buf(buf)

  return function(opts)
    local ok, filepath_or_err, count = state.remove(buf, opts.args)

    if not ok then
      vim.notify(filepath_or_err, vim.log.levels.ERROR)
      return
    end

    vim.notify(
      string.format("Removed: %s (%d remaining)", filepath_or_err, count),
      vim.log.levels.INFO
    )
  end
end

--- Create a handler for the `:AttachList` buffer-local command.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@return fun()
function C.list_handler(buf)
  buf = normalize_buf(buf)

  return function()
    local attachments = state.get(buf)

    if #attachments == 0 then
      print("No attachments. Try adding with :Attach")
      return
    end

    print(string.format("Attachments (%d):", #attachments))

    for i, path in ipairs(attachments) do
      local stat = vim.uv.fs_stat(path)
      local size_kb = stat and math.floor(stat.size / 1024) or 0
      print(string.format("  [%d] %s (%d KB)", i, path, size_kb))
    end
  end
end

--- Create a handler for the `:AttachOpen` buffer-local command.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@return fun()
function C.open_handler(buf)
  buf = normalize_buf(buf)

  return function()
    scratch.open(buf)
  end
end

--- Create completion source for `:AttachRemove`.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@return fun(): notmuch.AttachmentPath[]
function C.remove_completion(buf)
  buf = normalize_buf(buf)

  return function()
    return state.get(buf)
  end
end

--- Register attachment-related user commands on a draft buffer.
---
---@param buf integer? Draft buffer. Defaults to the current buffer.
---@return true
function C.setup_buffer(buf)
  buf = normalize_buf(buf)

  v.nvim_buf_create_user_command(buf, "Attach", C.attach_handler(buf), {
    nargs = 1,
    complete = "file",
    desc = "Attach a file to the current notmuch draft",
    force = true,
  })

  v.nvim_buf_create_user_command(buf, "AttachRemove", C.remove_handler(buf), {
    nargs = 1,
    complete = C.remove_completion(buf),
    desc = "Remove an attachment from the current notmuch draft",
    force = true,
  })

  v.nvim_buf_create_user_command(buf, "AttachList", C.list_handler(buf), {
    nargs = 0,
    desc = "List attachments for the current notmuch draft",
    force = true,
  })

  v.nvim_buf_create_user_command(buf, "AttachOpen", C.open_handler(buf), {
    nargs = 0,
    desc = "Open the attachment scratch buffer for the current notmuch draft",
    force = true,
  })

  return true
end

return C
