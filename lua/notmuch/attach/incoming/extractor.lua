-- notmuch.attach.incoming.extractor -- Cache/save extraction utilities

local E = {}

---@class NotmuchIncomingExtractorOptions
---@field cache_dir? string Cache root for incoming open/view extraction.
---@field force? boolean Re-extract even when cache file already exists.

-- -----------------------------------------------------------------------------
-- PRIVATE HELPERS
-- -----------------------------------------------------------------------------

local function default_cache_dir()
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "notmuch.nvim", "attachments")
end

local function normalize_message_id(message_id)
  return tostring(message_id or ""):gsub("^id:", "")
end

local function fallback_filename(part)
  local content_type = part.content_type or part["content-type"] or "application/octet-stream"
  local ext = content_type:match("/([%w.+-]+)$") or "bin"
  if ext == "plain" then
    ext = "txt"
  elseif ext == "octet-stream" then
    ext = "bin"
  end
  return "notmuch." .. ext
end

local function sanitize_component(value)
  value = tostring(value or "")
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  value = value:gsub("[/\\]", "-")
  value = value:gsub("[%z\r\n\t]", "_")
  if value == "" then
    return "unknown"
  end
  return value
end

local function ensure_parent_dir(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.mkdir(dir, "p") == 0 and vim.fn.isdirectory(dir) == 0 then
    return nil, "failed to create directory: " .. dir
  end
  return true
end

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

---Return deterministic cache filepath.
---@param message_id string Notmuch message id, with or without `id:` prefix.
---@param part table MimePart-like table.
---@param opts NotmuchIncomingExtractorOptions|nil
---@return string|nil path Cache filepath, or nil on validation failure.
---@return string|nil err Error message when path cannot be built.
function E.cache_path(message_id, part, opts)
  opts = opts or {}

  if type(part) ~= "table" then
    return nil, "part must be a table"
  end

  local normalized_id = normalize_message_id(message_id)
  if normalized_id == "" then
    return nil, "message_id is required"
  end

  if part.id == nil then
    return nil, "part.id is required"
  end

  local cache_dir = opts.cache_dir or default_cache_dir()
  local safe_message_id = sanitize_component(normalized_id)

  local filename = part.filename
  if filename == nil or filename == "" then
    filename = fallback_filename(part)
  end
  local safe_filename = sanitize_component(filename)

  return vim.fs.joinpath(cache_dir, safe_message_id, tostring(part.id) .. "-" .. safe_filename), nil
end

---Compute cache path, reuse if present unless force = true, otherwise extract.
---@param message_id string Notmuch message id, with or without `id:` prefix.
---@param part table MimePart-like table.
---@param opts NotmuchIncomingExtractorOptions|nil
---@return string|nil path Cached file path on success, or nil on failure.
---@return string|nil err Error message on failure.
function E.extract_to_cache(message_id, part, opts)
  opts = opts or {}

  local path, err = E.cache_path(message_id, part, opts)
  if not path then
    return nil, err
  end

  if not opts.force and vim.fn.filereadable(path) == 1 then
    return path, nil
  end

  return E.extract_to_path(message_id, part.id, path, opts)
end

---Extract one notmuch MIME part directly to a path using safe process execution.
---@param message_id string Notmuch message id, with or without `id:` prefix.
---@param part_id integer|string Notmuch MIME part id.
---@param path string Destination filepath.
---@param opts NotmuchIncomingExtractorOptions|nil
---@return string|nil path Destination path on success, or nil on failure.
---@return string|nil err Error message on failure.
function E.extract_to_path(message_id, part_id, path, opts)
  local normalized_id = normalize_message_id(message_id)
  if normalized_id == "" then
    return nil, "message_id is required"
  end

  if part_id == nil then
    return nil, "part_id is required"
  end

  if not path or path == "" then
    return nil, "path is required"
  end

  local ok, err = ensure_parent_dir(path)
  if not ok then
    return nil, err
  end

  local result = vim
    .system({
      "notmuch",
      "show",
      "--exclude=false",
      "--part=" .. tostring(part_id),
      "id:" .. normalized_id,
    }, { text = false })
    :wait()

  if result.code ~= 0 then
    return nil, result.stderr or "notmuch extraction failed"
  end

  local fd, open_err = io.open(path, "wb")
  if not fd then
    return nil, open_err
  end

  fd:write(result.stdout or "")
  fd:close()

  return path, nil
end

---Semantic wrapper for save flows.
---@param message_id string Notmuch message id, with or without `id:` prefix.
---@param part table MimePart-like table.
---@param path string User-selected destination filepath.
---@param opts NotmuchIncomingExtractorOptions|nil
---@return string|nil path Saved file path on success, or nil on failure.
---@return string|nil err Error message on failure.
function E.save_to_path(message_id, part, path, opts)
  if type(part) ~= "table" then
    return nil, "part must be a table"
  end

  return E.extract_to_path(message_id, part.id, path, opts)
end

return E
