--- notmuch.draft -- Draft management module for notmuch.nvim
---
--- Manages the process of creating new drafts, maintaining multiple unique
--- drafts for the reply, keeping open drafts for newly composed messages, etc.
--- in the user's data home directory, controlled by the config option
--- `drafts.folder`
---
--- Drafts by default live in the user's data home like so:
---   vim.fs.joinpath(vim.fn.stdpath("data"), "notmuch.nvim", "drafts")
---
--- Example:
---   $HOME/.local/share/nvim/notmuch.nvim/drafts
---
--- Sample directory structure:
---
---   drafts/         <- [Root drafts directory]
---   ├── compose/    <- [Drafts of newly composed emails]
---   │   ├── compose-20260704T103015Z-a1b2c3d4.eml
---   │   ├── compose-20260704T103015Z-a1b2c3d4.json
---   │   │
---   │   ├── compose-20260704T123400Z-9c0d1e2f.eml
---   │   └── compose-20260704T123400Z-9c0d1e2f.json
---   │
---   └── replies/    <- [Drafts of replies to other messages]
---       ├── 9c7e0a3b1d4e6f8.../  <- [SHA256 hash of original msg-id]
---       │   ├── message.json     <- [Sidecar metadata file of original msg]
---       │   │
---       │   ├── reply-20260704T104455Z-11112222.eml
---       │   ├── reply-20260704T104455Z-11112222.json
---       │   │
---       │   ├── reply-20260704T115902Z-33334444.eml
---       │   └── reply-20260704T115902Z-33334444.json
---       │
---       └── f6a90e17cc3a21.../
---           ├── message.json
---           │
---           ├── reply-20260704T130102Z-cc77dd88.eml
---           ├── reply-20260704T130102Z-cc77dd88.json
---           │
---           ├── reply-20260704T131500Z-ee99ff00.eml
---           ├── reply-20260704T131500Z-ee99ff00.json
---           │
---           ├── reply-20260704T133000Z-1122aabb.eml
---           └── reply-20260704T133000Z-1122aabb.json
---
--- Architecture:
---
--- - The drafts/ root directory is split into two subdirectories
---   - compose/ -- Drafts of newly composed emails
---   - replies/ -- Drafts of *replies* to other messages
---
--- - Compose
---   - For each draft, two files are coupled
---   - compose-<timestamp>-<random-hash>.eml
---     - The actual email content itself
---   - compose-<timestamp>-<random-hash>.json
---     - Sidecar file with attachments/metadata for persistence
---     - When loading the draft later, the sidecar keeps track of previously
---       kept attachments, etc.
---
--- - Replies
---   - Each reply has a subdirectory of the hash of the original message's ID
---   - This is in case you have multiple drafts for one message's reply
---   - `message.json` -- Sidecar metadata file of the original message
---   - `reply-<timestamp>-<random-hash>.eml`
---     - The actual email content itself
---   - `reply-<timestamp>-<random-hash>.json`
---     - Sidecar file with attachments/metadata for persistence

---@class notmuch.DraftMetadata
---@field schema_version integer Metadata schema version.
---@field kind "compose"|"reply" Draft kind.
---@field message_id? string Original message ID for reply drafts.
---@field attachments notmuch.AttachmentPath[] Attachment paths persisted with the draft.
---@field created_at string UTC creation timestamp.
---@field updated_at string UTC last-updated timestamp.
---@field sent_at any UTC sent timestamp, nil, or vim.NIL.

---@class notmuch.Draft
---@field kind "compose"|"reply" Draft kind.
---@field eml_path string Path to the draft `.eml` file.
---@field json_path string Path to the sidecar metadata `.json` file.
---@field metadata notmuch.DraftMetadata Draft metadata.
---@field subject? string Extracted subject for display.

local D = {}

local config = require("notmuch.config")

local function now_utc()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function random_suffix()
  return vim.fn.sha256(vim.fn.tempname()):sub(1, 8)
end

local function ensure_dir(path)
  local stat = vim.uv.fs_stat(path)

  if stat then
    if stat.type ~= "directory" then
      vim.notify("Draft path exists but is not a directory: " .. path, vim.log.levels.ERROR)
      return false
    end
    return true
  end

  local ok = vim.fn.mkdir(path, "p", 448) -- Octal: 0700 permissions drwx------
  if ok == 0 then
    vim.notify("Failed to create draft directory: " .. path, vim.log.levels.ERROR)
    return false
  end

  return true
end

local function extract_draft_header(eml_path, header_name)
  local ok, lines = pcall(vim.fn.readfile, eml_path, "", 50)
  if not ok then
    return nil
  end

  local prefix = header_name:lower() .. ":"

  for _, line in ipairs(lines) do
    if line == "" then
      break
    end

    if line:lower():sub(1, #prefix) == prefix then
      return vim.trim(line:sub(#prefix + 1))
    end
  end

  return nil
end

local function extract_draft_subject(eml_path)
  local subject = extract_draft_header(eml_path, "Subject")
  if not subject or subject == "" then
    return "[No subject]"
  end
  return subject
end

--- Return the directory used for newly composed drafts.
---
---@return string path
function D.compose_dir()
  return vim.fs.joinpath(config.options.drafts.folder, "compose")
end

--- Return the root directory used for reply drafts.
---
---@return string path
function D.replies_dir()
  return vim.fs.joinpath(config.options.drafts.folder, "replies")
end

--- Return the reply draft group directory for a message ID.
---
---@param message_id string Original message ID.
---@return string path
function D.reply_group_dir(message_id)
  return vim.fs.joinpath(D.replies_dir(), vim.fn.sha256(message_id))
end

--- Return the metadata path for a reply draft group.
---
---@param message_id string Original message ID.
---@return string path
function D.reply_group_metadata_path(message_id)
  return vim.fs.joinpath(D.reply_group_dir(message_id), "message.json")
end

--- Ensure the reply draft group directory and metadata file exist.
---
---@param message_id string Original message ID.
---@return string? dir Reply group directory, or nil on failure.
function D.ensure_reply_group(message_id)
  -- Validate the input `message_id` format
  if type(message_id) ~= "string" or message_id == "" then
    vim.notify("ensure_reply_group expected message id string", vim.log.levels.ERROR)
    return nil
  end

  -- Ensure reply group directory (<hash of message_id>/) exists or create
  local dir = D.reply_group_dir(message_id)
  if not ensure_dir(dir) then
    return nil
  end

  -- Ensure `<group_dir>/message.json` metadata file exists or create
  local metadata_path = D.reply_group_metadata_path(message_id)
  if not vim.uv.fs_stat(metadata_path) then
    local metadata = {
      schema_version = 1,
      message_id = message_id,
    }

    if not D.write_metadata(metadata_path, metadata) then
      return nil
    end

    return dir
  end

  -- If metadata file already exists, verify that valid message_id metadata
  local metadata = D.read_metadata(metadata_path)
  if not metadata then
    return nil
  end
  if metadata.message_id ~= message_id then
    vim.notify(
      "Reply draft group metadata does not match message id: " .. metadata_path,
      vim.log.levels.ERROR
    )
    return nil
  end

  return dir
end

--- Return the sidecar metadata path for an `.eml` draft path.
---
---@param eml_path string Draft `.eml` path.
---@return string path Sidecar `.json` path.
function D.sidecar_path(eml_path)
  local path = eml_path:gsub("%.eml$", ".json")
  return path
end

--- Read and decode draft metadata from a JSON sidecar file.
---
---@param path string Sidecar `.json` path.
---@return notmuch.DraftMetadata? metadata
function D.read_metadata(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    vim.notify("Failed to read draft metadata: " .. path, vim.log.levels.ERROR)
    return nil
  end

  local raw = table.concat(lines, "\n")
  local decode_ok, metadata = pcall(vim.json.decode, raw)
  if not decode_ok then
    vim.notify("Failed to decode draft metadata: " .. path, vim.log.levels.ERROR)
    return nil
  end

  return metadata
end

--- Encode and write draft metadata to a JSON sidecar file.
---
---@param path string Sidecar `.json` path.
---@param metadata notmuch.DraftMetadata|table Metadata to encode.
---@return boolean ok
function D.write_metadata(path, metadata)
  local ok, json = pcall(vim.json.encode, metadata)
  if not ok then
    vim.notify("Failed to encode draft metadata: " .. json, vim.log.levels.ERROR)
    return false
  end

  local write_ok = vim.fn.writefile({ json }, path)
  if write_ok ~= 0 then
    vim.notify("Failed to write draft metadata: " .. path, vim.log.levels.ERROR)
    return false
  end

  return true
end

--- Save attachments into an existing draft metadata sidecar.
---
---@param json_path string Sidecar `.json` path.
---@param attachments? notmuch.AttachmentPath[] Attachment paths.
---@return boolean ok
function D.save_attachments(json_path, attachments)
  local metadata = D.read_metadata(json_path)
  if not metadata then
    return false
  end

  metadata.attachments = attachments or {}
  metadata.updated_at = now_utc()

  return D.write_metadata(json_path, metadata)
end

--- Save a buffer's attachment list to its associated draft sidecar.
---
--- If the buffer is not associated with a draft sidecar, this is a no-op and
--- returns true.
---
---@param buf integer Draft buffer.
---@param attachments? notmuch.AttachmentPath[] Attachment paths.
---@return boolean ok
function D.save_buffer_attachments(buf, attachments)
  local ok, json_path = pcall(vim.api.nvim_buf_get_var, buf, "notmuch_draft_json_path")
  if not ok or not json_path then
    return true
  end

  return D.save_attachments(json_path, attachments)
end

--- Create a new compose draft and sidecar metadata file.
---
---@param lines string[] Email contents to write to the `.eml` file.
---@return notmuch.Draft? draft
function D.create_compose_draft(lines)
  if type(lines) ~= "table" then
    vim.notify("create_compose_draft expected lines table", vim.log.levels.ERROR)
    return nil
  end

  for i, line in ipairs(lines) do
    if type(line) ~= "string" then
      vim.notify(
        string.format("create_compose_draft expected line %d to be a string", i),
        vim.log.levels.ERROR
      )
      return nil
    end
  end

  local dir = D.compose_dir()

  if not ensure_dir(dir) then
    return nil
  end

  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local basename = string.format("compose-%s-%s", timestamp, random_suffix())

  local eml_path = vim.fs.joinpath(dir, basename .. ".eml")
  local json_path = D.sidecar_path(eml_path)

  local created_at = now_utc()

  local metadata = {
    schema_version = 1,
    kind = "compose",
    attachments = {},
    created_at = created_at,
    updated_at = created_at,
    sent_at = vim.NIL,
  }

  local ok_eml = vim.fn.writefile(lines, eml_path)
  if ok_eml ~= 0 then
    vim.notify("Failed to write compose draft: " .. eml_path, vim.log.levels.ERROR)
    return nil
  end

  if not D.write_metadata(json_path, metadata) then
    vim.fn.delete(eml_path)
    return nil
  end

  return {
    kind = "compose",
    eml_path = eml_path,
    json_path = json_path,
    metadata = metadata,
  }
end

--- Create a new reply draft and sidecar metadata file.
---
---@param message_id string Original message ID being replied to.
---@param lines string[] Email contents to write to the `.eml` file.
---@return notmuch.Draft? draft
function D.create_reply_draft(message_id, lines)
  -- Validate message_id
  if type(message_id) ~= "string" or message_id == "" then
    vim.notify("create_reply_draft expected message id string", vim.log.levels.ERROR)
    return nil
  end

  -- Validate lines table
  if type(lines) ~= "table" then
    vim.notify("create_reply_draft expected lines table", vim.log.levels.ERROR)
    return nil
  end

  -- Validate lines elements
  for i, line in ipairs(lines) do
    if type(line) ~= "string" then
      vim.notify(
        string.format("create_reply_draft expected line %d to be a string", i),
        vim.log.levels.ERROR
      )
      return nil
    end
  end

  local dir = D.ensure_reply_group(message_id)
  if not dir then
    return nil
  end

  -- Prepare metadata for the reply
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local basename = string.format("reply-%s-%s", timestamp, random_suffix())
  local eml_path = vim.fs.joinpath(dir, basename .. ".eml")
  local json_path = D.sidecar_path(eml_path)
  local created_at = now_utc()
  local metadata = {
    schema_version = 1,
    kind = "reply",
    message_id = message_id,
    attachments = {},
    created_at = created_at,
    updated_at = created_at,
    sent_at = vim.NIL,
  }

  -- Write `.eml` file with reply mail content
  local ok_eml = vim.fn.writefile(lines, eml_path)
  if ok_eml ~= 0 then
    vim.notify("Failed to write reply draaft: " .. eml_path, vim.log.levels.ERROR)
    return nil
  end

  -- Write metadata to json, rollback if failed
  if not D.write_metadata(json_path, metadata) then
    vim.fn.delete(eml_path)
  end

  return {
    kind = "reply",
    eml_path = eml_path,
    json_path = json_path,
    metadata = metadata,
    subject = extract_draft_subject(eml_path),
  }
end

--- Load a compose draft from an `.eml` path and its sidecar metadata.
---
---@param eml_path string Draft `.eml` path.
---@return notmuch.Draft? draft
function D.load_compose_draft(eml_path)
  local json_path = D.sidecar_path(eml_path)
  local metadata = D.read_metadata(json_path)
  if not metadata then
    return nil
  end

  return {
    kind = "compose",
    eml_path = eml_path,
    json_path = json_path,
    metadata = metadata,
    subject = extract_draft_subject(eml_path),
  }
end

--- Load a reply draft from an `.eml` path and its sidecar metadata.
---
---@param eml_path string Draft `.eml` path.
---@return notmuch.Draft? draft
function D.load_reply_draft(eml_path)
  -- Validate eml_path
  if type(eml_path) ~= "string" or eml_path == "" then
    vim.notify("load_reply_draft expected eml path string", vim.log.levels.ERROR)
    return nil
  end

  -- Fetch metadata
  local json_path = D.sidecar_path(eml_path)
  local metadata = D.read_metadata(json_path)
  if not metadata then
    return nil
  end

  -- Defensively check against wrong `kind`
  if metadata.kind ~= "reply" then
    vim.notify("Draft is not a reply draft: " .. eml_path, vim.log.levels.ERROR)
    return nil
  end

  return {
    kind = "reply",
    eml_path = eml_path,
    json_path = json_path,
    metadata = metadata,
    subject = extract_draft_subject(eml_path),
  }
end

local function is_unsent(draft)
  return draft.metadata.sent_at == nil or draft.metadata.sent_at == vim.NIL
end

--- List compose drafts sorted by most recently updated.
---
--- Sent drafts are included only when enabled by configuration.
---
---@return notmuch.Draft[]? drafts
function D.list_compose_drafts()
  local dir = D.compose_dir()
  if not ensure_dir(dir) then
    return nil
  end

  local paths = vim.fn.globpath(dir, "*.eml", false, true)
  local drafts = {}

  for _, eml_path in ipairs(paths) do
    local draft = D.load_compose_draft(eml_path)

    if
      draft
      and draft.kind == "compose"
      and (config.options.drafts.show_sent_drafts or is_unsent(draft))
    then
      table.insert(drafts, draft)
    end
  end

  table.sort(drafts, function(a, b)
    local a_time = a.metadata.updated_at or a.metadata.created_at or ""
    local b_time = b.metadata.updated_at or b.metadata.created_at or ""

    return a_time > b_time
  end)

  return drafts
end

--- List reply drafts for a message ID sorted by most recently updated.
---
--- Sent drafts are included only when enabled by configuration.
---
---@param message_id string Original message ID.
---@return notmuch.Draft[]? drafts
function D.list_reply_drafts(message_id)
  -- Validate message_id input
  if type(message_id) ~= "string" or message_id == "" then
    vim.notify("list_reply_drafts expected message id string", vim.log.levels.ERROR)
    return nil
  end

  -- Fetch reply group dir (don't create new one if it doesn't exist already)
  local dir = D.reply_group_dir(message_id)
  local stat = vim.uv.fs_stat(dir)
  if not stat then
    return nil
  end

  -- Validate reply group dir is a directory if exists
  if stat.type ~= "directory" then
    vim.notify("Reply drafts path is not a directory: " .. dir, vim.log.levels.ERROR)
    return nil
  end

  -- Get all `.eml` files in this reply group
  local paths = vim.fn.globpath(dir, "*.eml", false, true)
  local drafts = {}
  for _, eml_path in ipairs(paths) do
    local draft = D.load_reply_draft(eml_path)
    if
      draft
      and draft.kind == "reply"
      and draft.metadata.message_id == message_id
      and (config.options.drafts.show_sent_drafts or is_unsent(draft))
    then
      table.insert(drafts, draft)
    end
  end

  -- Sort by updated/created timestamp, descending
  table.sort(drafts, function(a, b)
    local a_time = a.metadata.updated_at or a.metadata.created_at or ""
    local b_time = b.metadata.updated_at or b.metadata.created_at or ""

    return a_time > b_time
  end)

  return drafts
end

--- List all reply drafts sorted by most recently updated.
---
--- Sent drafts are included only when enabled by configuration.
---
---@return notmuch.Draft[]? drafts
function D.list_all_reply_drafts()
  -- Check and ensure replies/ dir exists
  local dir = D.replies_dir()
  local stat = vim.uv.fs_stat(dir)
  if not stat then
    return {}
  end

  if stat.type ~= "directory" then
    vim.notify("Reply drafts path is not a directory: " .. dir, vim.log.levels.ERROR)
    return nil
  end

  local paths = vim.fn.globpath(dir, "*/*.eml", false, true)
  local drafts = {}

  for _, eml_path in ipairs(paths) do
    local draft = D.load_reply_draft(eml_path)
    if
      draft
      and draft.kind == "reply"
      and (config.options.drafts.show_sent_drafts or is_unsent(draft))
    then
      table.insert(drafts, draft)
    end
  end

  table.sort(drafts, function(a, b)
    local a_time = a.metadata.updated_at or a.metadata.created_at or ""
    local b_time = b.metadata.updated_at or b.metadata.created_at or ""
    return a_time > b_time
  end)

  return drafts
end

--- List all compose and reply drafts sorted by most recently updated.
---
---@return notmuch.Draft[] drafts
function D.list_all_drafts()
  local drafts = {}

  for _, draft in ipairs(D.list_compose_drafts() or {}) do
    table.insert(drafts, draft)
  end

  for _, draft in ipairs(D.list_all_reply_drafts() or {}) do
    table.insert(drafts, draft)
  end

  table.sort(drafts, function(a, b)
    local a_time = a.metadata.updated_at or a.metadata.created_at or ""
    local b_time = b.metadata.updated_at or b.metadata.created_at or ""
    return a_time > b_time
  end)

  return drafts
end

--- Mark a draft sidecar as sent.
---
---@param json_path string Sidecar `.json` path.
---@return boolean ok
function D.mark_sent(json_path)
  local metadata = D.read_metadata(json_path)
  if not metadata then
    return false
  end

  local now = now_utc()
  metadata.sent_at = now
  metadata.updated_at = now

  return D.write_metadata(json_path, metadata)
end

--- Delete a draft's `.eml` file and sidecar metadata file.
---
---@param draft_or_eml_path notmuch.Draft|string Draft object or `.eml` path.
---@return boolean ok
function D.delete_draft(draft_or_eml_path)
  local eml_path
  local json_path

  if type(draft_or_eml_path) == "table" then
    eml_path = draft_or_eml_path.eml_path
    if eml_path then
      json_path = draft_or_eml_path.json_path or D.sidecar_path(eml_path)
    end
  elseif type(draft_or_eml_path) == "string" then
    eml_path = draft_or_eml_path
    json_path = D.sidecar_path(eml_path)
  else
    vim.notify("delete_draft expected draft object or eml path", vim.log.levels.ERROR)
    return false
  end

  if not eml_path or eml_path == "" then
    vim.notify("delete_draft missing eml path", vim.log.levels.ERROR)
    return false
  end

  if not eml_path:match("%.eml$") then
    vim.notify("delete_draft expected .eml path: " .. eml_path, vim.log.levels.ERROR)
    return false
  end

  local ok = true

  if vim.uv.fs_stat(eml_path) then
    if vim.fn.delete(eml_path) ~= 0 then
      vim.notify("Failed to delete draft file: " .. eml_path, vim.log.levels.ERROR)
      ok = false
    end
  end

  if json_path and vim.uv.fs_stat(json_path) then
    if vim.fn.delete(json_path) ~= 0 then
      vim.notify("Failed to delete draft metadata: " .. json_path, vim.log.levels.ERROR)
      ok = false
    end
  end

  return ok
end

return D
