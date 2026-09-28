local M = {}

---Stream and incrementally decode a JSON search without retaining complete stdout.
---@param query string
---@param handlers table { on_records?, on_complete? }
---@param options? table { sort?, records_per_tick?, bytes_per_tick? }
---@return table|nil request Cancellable request handle.
function M.stream_notmuch_search(query, handlers, options)
  options = options or {}
  local parser = require("notmuch.search.stream").new()
  local model = require("notmuch.search.model")
  local seen, index = {}, 0
  local request = {
    cancelled = false,
    scheduled = false,
    stdout_done = false,
    exited = nil,
    stderr = "",
    completed = false,
  }

  function request:kill(signal)
    if self.cancelled then
      return
    end
    self.cancelled = true
    if self.process then
      pcall(self.process.kill, self.process, signal or 15)
    end
  end

  local function complete(result)
    if request.completed or request.cancelled then
      return
    end
    request.completed = true
    result.stderr = request.stderr ~= "" and request.stderr or result.stderr
    if handlers.on_complete then
      handlers.on_complete(result)
    end
  end

  local drain
  local function schedule_drain()
    if request.scheduled or request.cancelled or request.completed then
      return
    end
    request.scheduled = true
    vim.schedule(function()
      request.scheduled = false
      drain()
    end)
  end

  drain = function()
    if request.cancelled or request.completed then
      return
    end
    local objects, parse_error =
      parser:drain(options.records_per_tick or 64, options.bytes_per_tick or 128 * 1024)
    local records = {}
    if not parse_error then
      for _, text in ipairs(objects) do
        index = index + 1
        local record, err = model.decode_record(text, index, seen)
        if not record then
          parse_error = err
          break
        end
        records[#records + 1] = record
      end
    end
    if #records > 0 and handlers.on_records then
      handlers.on_records(records)
    end
    if parse_error then
      if request.process then
        pcall(request.process.kill, request.process, 15)
      end
      complete({ code = -1, parse_error = parse_error })
      return
    end
    if parser:has_input() then
      schedule_drain()
      return
    end
    if request.stdout_done and request.exited then
      if request.exited.code == 0 then
        local _, finish_error = parser:finish()
        if finish_error then
          complete({ code = -1, signal = request.exited.signal, parse_error = finish_error })
          return
        end
      end
      complete(request.exited)
    end
  end

  local args = { "notmuch", "search", "--format=json" }
  if options.sort then
    args[#args + 1] = "--sort=" .. options.sort
  end
  args[#args + 1] = query
  local ok, process = pcall(vim.system, args, {
    text = true,
    stdout = function(err, data)
      if request.cancelled or request.completed then
        return
      end
      if err then
        request.stderr = (request.stderr .. tostring(err)):sub(1, 8192)
      end
      if data then
        parser:feed(data)
      else
        request.stdout_done = true
      end
      schedule_drain()
    end,
    stderr = function(_, data)
      if data and #request.stderr < 8192 then
        request.stderr = (request.stderr .. data):sub(1, 8192)
      end
    end,
  }, function(result)
    request.exited = result
    schedule_drain()
  end)
  if not ok then
    vim.schedule(function()
      complete({ code = -1, stderr = tostring(process) })
    end)
    return request
  end
  request.process = process
  return request
end

return M
