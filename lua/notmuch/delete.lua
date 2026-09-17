local d = {}
local nm = require("notmuch")
local r = require("notmuch.refresh")

local DELETE_QUERY = "tag:del"

-- Purging operates on the whole mail database. Keep a module-level guard so two
-- purge pipelines cannot delete/reindex concurrently.
local purge_in_progress = false

---@class notmuch.PurgeSystemResult
---@field code integer Process exit code.
---@field stdout? string Captured standard output.
---@field stderr? string Captured standard error.

---@class notmuch.PurgeFailure
---@field path string File that could not be removed.
---@field error string Error returned by libuv.

---@class notmuch.PurgeResult
---@field deleted string[] Files removed by this purge.
---@field missing string[] Files that were already absent.
---@field failed notmuch.PurgeFailure[] Files that could not be removed.

---Notify the user that a Notmuch subprocess failed.
---@param action string Human-readable description of the attempted operation.
---@param result notmuch.PurgeSystemResult Completed process result.
local function notify_command_failure(action, result)
  local stderr = vim.trim(result.stderr or "")
  local detail = stderr ~= "" and (":\n" .. stderr) or ""
  vim.notify(
    ("notmuch.nvim: %s failed (exit code %d)%s"):format(action, result.code or -1, detail),
    vim.log.levels.ERROR
  )
end

---Parse and deduplicate the NUL-delimited output from `notmuch search --format=text0`.
---
---NUL delimiters preserve paths containing whitespace or newlines. Deduplication
---prevents a second unlink attempt if Notmuch reports the same indexed file more
---than once.
---@param stdout string|nil Raw standard output from Notmuch.
---@return string[] paths Unique, non-empty file paths in their original order.
local function unique_paths(stdout)
  local paths = vim.split(stdout or "", "\0", { plain = true, trimempty = true })
  local seen = {}
  local unique = {}

  for _, path in ipairs(paths) do
    if path ~= "" and not seen[path] then
      seen[path] = true
      unique[#unique + 1] = path
    end
  end

  return unique
end

---Find the files currently represented by messages carrying the `del` tag.
---
---The argv form of `vim.system()` intentionally bypasses shell parsing. The
---callback receives nil after a process failure, which stops the purge before
---any filesystem changes occur.
---@param callback fun(files: string[]|nil)
local function find_deleted_files(callback)
  local ok, err = pcall(
    vim.system,
    {
      "notmuch",
      "search",
      "--output=files",
      "--format=text0",
      DELETE_QUERY,
    },
    {},
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        notify_command_failure("searching for deleted mail", result)
        callback(nil)
        return
      end

      callback(unique_paths(result.stdout))
    end)
  )

  if not ok then
    vim.notify(
      "notmuch.nvim: failed to start purge search: " .. tostring(err),
      vim.log.levels.ERROR
    )
    callback(nil)
  end
end

---Ask for final confirmation after taking a snapshot of the files to remove.
---
---The safe default is Cancel. The displayed count therefore matches the exact
---snapshot passed to the unlink stage rather than an earlier search-buffer view.
---@param count integer Number of unique files in the purge snapshot.
---@return boolean confirmed True only when the user explicitly selects Delete.
local function confirm_purge(count)
  local choice = vim.fn.confirm(
    ("Permanently delete %d mail file%s?\nThis cannot be undone."):format(
      count,
      count == 1 and "" or "s"
    ),
    "&Delete\n&Cancel",
    2
  )

  return choice == 1
end

---Remove every file asynchronously and aggregate individual outcomes.
---
---All unlink attempts are allowed to finish, even after one fails. This lets the
---caller reindex successful removals and report partial failure accurately.
---@param files string[] Unique paths to remove.
---@param callback fun(result: notmuch.PurgeResult)
local function unlink_files(files, callback)
  local pending = #files
  ---@type notmuch.PurgeResult
  local result = {
    deleted = {},
    missing = {},
    failed = {},
  }

  ---Record one libuv completion and invoke the aggregate callback after all
  ---outstanding paths have completed.
  ---@param path string
  ---@param err? string
  local function complete(path, err)
    if not err then
      result.deleted[#result.deleted + 1] = path
    elseif tostring(err):find("ENOENT", 1, true) then
      -- Another mail process may remove a file between search and unlink. It is
      -- already in the desired state, but still requires `notmuch new`.
      result.missing[#result.missing + 1] = path
    else
      result.failed[#result.failed + 1] = {
        path = path,
        error = tostring(err),
      }
    end

    pending = pending - 1
    if pending == 0 then
      -- libuv callbacks run outside normal Neovim API context. Resume the purge
      -- pipeline on the main event loop before invoking vim.system/UI functions.
      vim.schedule(function()
        callback(result)
      end)
    end
  end

  for _, path in ipairs(files) do
    local ok, err = pcall(vim.uv.fs_unlink, path, function(unlink_err)
      complete(path, unlink_err)
    end)

    if not ok then
      -- pcall's second return is typed as a union of fs_unlink's possible
      -- success values and its thrown error. In this branch it is the thrown
      -- error, so normalize it to the string expected by complete().
      complete(path, tostring(err))
    end
  end
end

---Update the Notmuch index after all filesystem deletion attempts complete.
---
---Reindexing is required after both successful deletions and ENOENT outcomes so
---stale database entries disappear. It is also run after partial failure because
---the successfully removed subset cannot be rolled back.
---@param callback fun(ok: boolean, result: notmuch.PurgeSystemResult)
local function reindex(callback)
  local ok, err = pcall(
    vim.system,
    { "notmuch", "new" },
    {},
    vim.schedule_wrap(function(result)
      callback(result.code == 0, result)
    end)
  )

  if not ok then
    callback(false, {
      code = -1,
      stderr = tostring(err),
    })
  end
end

---Refresh or invalidate the search buffer from which purge was started.
---
---Never call the existing current-buffer refresh function against an unrelated
---buffer after asynchronous work. A hidden origin is deleted so reopening the
---same query creates fresh results; a visible non-current origin is left alone.
---@param buf integer Originating search buffer id.
local function refresh_originating_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if vim.api.nvim_get_current_buf() == buf then
    r.refresh_search_buffer()
  elseif vim.fn.bufwinid(buf) == -1 then
    -- Do not leave a hidden search buffer containing stale purge results. The
    -- query will be run again the next time the user opens it.
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

---Format a bounded list of unlink failures for a user notification.
---@param failures notmuch.PurgeFailure[]
---@return string details At most five failures plus an omitted-count summary.
local function failure_details(failures)
  local lines = {}
  local shown = math.min(#failures, 5)

  for i = 1, shown do
    local failure = failures[i]
    lines[#lines + 1] = ("- %s: %s"):format(failure.path, failure.error)
  end

  if #failures > shown then
    lines[#lines + 1] = ("...and %d more"):format(#failures - shown)
  end

  return table.concat(lines, "\n")
end

---Report the combined filesystem and indexing outcome without claiming that
---irreversible deletions failed merely because the subsequent reindex failed.
---@param result notmuch.PurgeResult Aggregated unlink outcomes.
---@param index_ok boolean Whether `notmuch new` completed successfully.
---@param index_result notmuch.PurgeSystemResult Completed reindex result.
local function report_result(result, index_ok, index_result)
  local deleted = #result.deleted
  local missing = #result.missing
  local failed = #result.failed

  if not index_ok then
    local stderr = vim.trim(index_result.stderr or "")
    local detail = stderr ~= "" and (":\n" .. stderr) or ""
    vim.notify(
      ("notmuch.nvim: purge changed the filesystem (%d deleted, %d already missing, %d failed), but `notmuch new` failed (exit code %d)%s\nRun `notmuch new` manually."):format(
        deleted,
        missing,
        failed,
        index_result.code or -1,
        detail
      ),
      vim.log.levels.ERROR
    )
    return
  end

  if failed > 0 then
    local level = deleted + missing == 0 and vim.log.levels.ERROR or vim.log.levels.WARN
    vim.notify(
      ("notmuch.nvim: purged %d of %d mail files; %d could not be deleted.\n%s"):format(
        deleted + missing,
        deleted + missing + failed,
        failed,
        failure_details(result.failed)
      ),
      level
    )
    return
  end

  local missing_note = missing > 0 and ("; " .. missing .. " already missing") or ""
  vim.notify(
    ("notmuch.nvim: purged %d mail file%s%s."):format(
      deleted,
      deleted == 1 and "" or "s",
      missing_note
    ),
    vim.log.levels.INFO
  )
end

---Coordinate the asynchronous purge pipeline for one search buffer.
---
---The order is deliberately: snapshot files, confirm the snapshot, unlink all
---files, reindex, then refresh/report. Every early return releases the global
---guard so a later purge can proceed.
---@param origin_buf integer Search buffer in which the one-shot DD action began.
local function purge_deleted(origin_buf)
  if purge_in_progress then
    vim.notify("notmuch.nvim: a mail purge is already in progress", vim.log.levels.WARN)
    return
  end

  purge_in_progress = true

  local function finish()
    purge_in_progress = false
  end

  find_deleted_files(function(files)
    if not files then
      finish()
      return
    end

    if #files == 0 then
      vim.notify("notmuch.nvim: no deleted mail files found", vim.log.levels.INFO)
      finish()
      return
    end

    if not confirm_purge(#files) then
      finish()
      return
    end

    unlink_files(files, function(unlink_result)
      reindex(function(index_ok, index_result)
        -- Release the guard before UI refresh/reporting so an unrelated UI
        -- error cannot leave purging permanently locked.
        finish()

        if index_ok then
          refresh_originating_buffer(origin_buf)
        end

        report_result(unlink_result, index_ok, index_result)
      end)
    end)
  end)
end

---Open the deleted-mail preview and arm its one-shot `DD` purge mapping.
---
---Pressing `DD` removes that temporary mapping before any asynchronous work
---begins. Cancelling or retrying therefore requires an intentional `D` followed
---by `DD`, reducing the chance of an accidental repeated purge.
d.purge_del = function()
  if purge_in_progress then
    vim.notify("notmuch.nvim: a mail purge is already in progress", vim.log.levels.WARN)
    return
  end

  nm.search_terms(DELETE_QUERY)
  local buf = vim.api.nvim_get_current_buf()

  vim.keymap.set("n", "DD", function()
    -- DD is a one-shot action. Re-enter purge preview with D to arm it again.
    pcall(vim.keymap.del, "n", "DD", { buffer = buf })
    purge_deleted(buf)
  end, { buffer = buf, desc = "Permanently purge deleted mail" })
end

return d
