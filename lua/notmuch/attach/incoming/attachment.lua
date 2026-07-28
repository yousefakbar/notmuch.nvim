-- notmuch.attach.incoming.attachment -- Attachment object builder

local A = {}

---@class NotmuchIncomingAttachment
---@field path string|nil Extracted local file path. Used for open/view flows.
---@field part NotmuchIncomingAttachmentPart Normalized MIME part metadata.
---@field message NotmuchIncomingAttachmentMessage Message metadata.

---@class NotmuchIncomingAttachmentPart
---@field id integer|string Notmuch MIME part ID.
---@field content_type string MIME content type from notmuch metadata.
---@field filename string Attachment filename from MIME metadata.
---@field disposition string MIME content disposition, `inline`/`attachment`.
---@field size integer Size in bytes, or 0 when unknown.
---@field ext string Lowercase filename extension without leading dot.
---@field raw table Original MIME part table, from notmuch JSON output.

---@class NotmuchIncomingAttachmentMessage
---@field id string Raw notmuch message ID without the `id:` prefix.

-- -----------------------------------------------------------------------------
-- PRIVATE HELPERS
-- -----------------------------------------------------------------------------

local function normalize_message_id(id)
  return tostring(id or ""):gsub("^id:", "")
end

local function get_ext(filename)
  local ext = filename:match("%.([^%.]+)$")
  return ext and ext:lower() or ""
end

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

---From part
---@param part table Existing MimePart-like table from notmuch.attach.parts
---@param message_id string Raw message ID, preferably without `id:` prefix
---@param path string|nil Extracted local path
---@return NotmuchIncomingAttachment
function A.from_part(part, message_id, path)
  if type(part) ~= "table" then
    error("notmuch.attach.incoming.attachment.from_part: part must be a table")
  end

  local normalized_message_id = normalize_message_id(message_id)
  if normalized_message_id == "" then
    error("notmuch.attach.incoming.attachment.from_part: message_id is required")
  end

  local filename = part.filename or ""
  local content_type = part.content_type or part["content-type"] or "application/octet-stream"
  local disposition = part.disposition or part["content-disposition"] or "inline"
  local size = part.size or part["content-length"] or 0

  return {
    path = path,

    part = {
      id = part.id,
      content_type = content_type,
      filename = filename,
      disposition = disposition,
      size = size,
      ext = get_ext(filename),
      raw = part,
    },

    message = {
      id = normalized_message_id,
    },
  }
end

return A
