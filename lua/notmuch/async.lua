local M = {}

---Run a JSON search without blocking Neovim or touching any buffers.
---@param query string
---@param callback fun(result: table)
---@return table|nil process Cancellable vim.SystemObj; start errors also reach callback.
function M.run_notmuch_search(query, callback)
  local done = vim.schedule_wrap(callback)
  local ok, process = pcall(vim.system, {
    "notmuch",
    "search",
    "--format=json",
    query,
  }, { text = true }, done)
  if not ok then
    done({ code = -1, stderr = tostring(process) })
    return nil
  end
  return process
end

return M
