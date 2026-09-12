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

  -- Trims leading and trailing whitespace
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  -- Replace "\" and "/" with "-"
  value = value:gsub("[/\\]", "-")
  -- Replace null and newlines with "_"
  value = value:gsub("[%z\r\n\t]", "_")

  if value == "" then
    return "unknown"
  end

  return value
end

local PRIVATE_DIR_MODE = 448 -- 0700

local function ensure_private_cache_dir(dir)
  if vim.fn.mkdir(dir, "p", PRIVATE_DIR_MODE) == 0 and vim.fn.isdirectory(dir) == 0 then
    return nil, "failed to create cache directory: " .. dir
  end

  -- Unix permission bits do not provide the same guarantees on Windows.
  if vim.fn.has("win32") == 0 then
    local secured, chmod_err = vim.uv.fs_chmod(dir, PRIVATE_DIR_MODE)
    if not secured then
      return nil, "failed to secure cache directory: " .. tostring(chmod_err)
    end
  end

  return true
end

local function ensure_parent_dir(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.mkdir(dir, "p") == 0 and vim.fn.isdirectory(dir) == 0 then
    return nil, "failed to create directory: " .. dir
  end
  return true
end

local function remove_file(path)
  if path then
    vim.uv.fs_unlink(path)
  end
end

local function write_all(fd, data)
  local offset = 1

  while offset <= #data do
    local written, err = vim.uv.fs_write(fd, data:sub(offset))
    if not written then
      return nil, err
    end
    if written == 0 then
      return nil, "attachment write made no progress"
    end
    offset = offset + written
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

  local part_id = tonumber(part.id)
  if not part_id or part_id < 1 or part_id ~= math.floor(part_id) then
    return nil, "part.id must be a positive integer"
  end

  local cache_dir = opts.cache_dir or default_cache_dir()
  local safe_message_id = vim.fn.sha256(normalized_id)

  local filename = part.filename
  if filename == nil or filename == "" then
    filename = fallback_filename(part)
  end
  local safe_filename = sanitize_component(filename)

  return vim.fs.joinpath(cache_dir, safe_message_id, tostring(part_id) .. "-" .. safe_filename), nil
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

  -- Cache paths have the form:
  -- <cache-root>/<message-id-hash>/<part-id>-<filename>
  local cache_parent = vim.fn.fnamemodify(path, ":h")
  local secured, secure_err = ensure_private_cache_dir(cache_parent)
  if not secured then
    return nil, secure_err
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

  local temp_fd, temp_path = vim.uv.fs_mkstemp(path .. ".tmp-XXXXXX")
  if not temp_fd then
    return nil, "failed to create temporary extraction file: " .. tostring(temp_path)
  end

  local write_err
  local system_ok, result = pcall(function()
    return vim
      .system({
        "notmuch",
        "show",
        "--exclude=false",
        "--part=" .. tostring(part_id),
        "id:" .. normalized_id,
      }, {
        text = false,
        stdout = function(read_err, data)
          if read_err then
            write_err = write_err or read_err
          elseif data and data ~= "" and not write_err then
            local written, err = write_all(temp_fd, data)
            if not written then
              write_err = err or "failed to write attachment"
            end
          end
        end,
      })
      :wait()
  end)

  -- Close temporary file descriptor after streaming write operation is complete
  local closed, close_err = vim.uv.fs_close(temp_fd)

  -- Check for `vim.system()` errors (ie. `notmuch` fails to launch)
  if not system_ok then
    remove_file(temp_path)
    return nil, "failed to run notmuch extraction: " .. tostring(result)
  end

  -- Check for write errors during stdout streaming to temp file
  if write_err then
    remove_file(temp_path)
    return nil, "failed to write attachment: " .. tostring(write_err)
  end

  -- Check for error exit codes from the `vim.system()` call
  if result.code ~= 0 then
    remove_file(temp_path)
    local process_err = result.stderr
    if not process_err or process_err == "" then
      process_err = "notmuch extraction failed"
    end
    return nil, process_err
  end

  -- Check if temp file closed properly before we attempt renaming
  if not closed then
    remove_file(temp_path)
    return nil, "failed to close attachment file: " .. tostring(close_err)
  end

  -- Rename/move the temp file to the final cache path
  local renamed, rename_err = vim.uv.fs_rename(temp_path, path)
  if not renamed then
    remove_file(temp_path)
    return nil, "failed to finalize attachment: " .. tostring(rename_err)
  end

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
