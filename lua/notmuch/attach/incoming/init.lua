local I = {}

local attachment = require("notmuch.attach.incoming.attachment")
local extractor = require("notmuch.attach.incoming.extractor")
local opener = require("notmuch.attach.incoming.opener")
local viewer = require("notmuch.attach.incoming.viewer")
local renderer = require("notmuch.attach.incoming.renderer")
local config = require("notmuch.config")

local function incoming_config()
  return ((config.options or {}).attach or {}).incoming or {}
end

local function extract_attachment(part, message_id, incoming_opts)
  local path, err = extractor.extract_to_cache(message_id, part, {
    cache_dir = incoming_opts.cache_dir,
  })
  if not path then
    return nil, err
  end

  return attachment.from_part(part, message_id, path), nil
end

---Open an incoming MIME part externally.
---@param part table MimePart-like table.
---@param message_id string Notmuch message id, with or without `id:` prefix.
---@param opts table|nil Incoming attachment config override.
---@return boolean ok True when the attachment was opened.
---@return string|nil err Error message on failure.
function I.open_part(part, message_id, opts)
  local incoming_opts = opts or incoming_config()
  local att, err = extract_attachment(part, message_id, incoming_opts)
  if not att then
    vim.notify(err, vim.log.levels.ERROR)
    return false, err
  end

  return opener.open(att, incoming_opts.open or {})
end

---View an incoming MIME part internally.
---@param part table MimePart-like table.
---@param message_id string Notmuch message id, with or without `id:` prefix.
---@param opts table|nil Incoming attachment config override.
---@return table|nil rendered Rendered preview handles from renderer.render().
---@return string|nil err Error message on failure.
function I.view_part(part, message_id, opts)
  local incoming_opts = opts or incoming_config()
  local att, err = extract_attachment(part, message_id, incoming_opts)
  if not att then
    vim.notify(err, vim.log.levels.ERROR)
    return nil, err
  end

  local result, view_err = viewer.view(att, incoming_opts.view or {})
  if not result then
    vim.notify(view_err, vim.log.levels.ERROR)
    return nil, view_err
  end

  return renderer.render(result, att, incoming_opts.view or {}), nil
end

return I
