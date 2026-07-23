local H = {}

function H.ok(value, msg)
  if not value then
    error(msg or "expected truthy value", 2)
  end
end

function H.eq(expected, actual, msg)
  if expected ~= actual then
    error(
      (msg or "values are not equal")
        .. "\nexpected: "
        .. vim.inspect(expected)
        .. "\nactual:   "
        .. vim.inspect(actual),
      2
    )
  end
end

function H.same(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(
      (msg or "values are not deeply equal")
        .. "\nexpected: "
        .. vim.inspect(expected)
        .. "\nactual:   "
        .. vim.inspect(actual),
      2
    )
  end
end

function H.matches(text, pattern, msg)
  text = tostring(text)
  if not text:match(pattern) then
    error(
      (msg or "expected text to match pattern") .. "\npattern: " .. pattern .. "\ntext:    " .. text,
      2
    )
  end
end

function H.contains(haystack, needle, msg)
  local text
  if type(haystack) == "table" then
    text = table.concat(haystack, "\n")
  else
    text = tostring(haystack)
  end
  if not text:find(needle, 1, true) then
    error(
      (msg or "expected text to contain needle") .. "\nneedle: " .. needle .. "\ntext:   " .. text,
      2
    )
  end
end

function H.list_contains(list, value, msg)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  error(
    (msg or "expected list to contain value")
      .. "\nvalue: "
      .. vim.inspect(value)
      .. "\nlist:  "
      .. vim.inspect(list),
    2
  )
end

function H.system(args)
  local result = vim.system(args, { text = true }):wait()
  if result.code ~= 0 then
    error(
      "command failed: "
        .. table.concat(args, " ")
        .. "\nstdout: "
        .. (result.stdout or "")
        .. "\nstderr: "
        .. (result.stderr or ""),
      2
    )
  end
  return result.stdout or ""
end

function H.wait_until(predicate, timeout_ms, interval_ms)
  timeout_ms = timeout_ms or 2000
  interval_ms = interval_ms or 20
  local deadline = vim.uv.now() + timeout_ms
  local last_err

  while vim.uv.now() < deadline do
    local ok, result = pcall(predicate)
    if ok and result then
      return result
    end
    if not ok then
      last_err = result
    end
    vim.wait(interval_ms)
  end

  error("timed out waiting for condition" .. (last_err and (": " .. tostring(last_err)) or ""), 2)
end

function H.current_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

function H.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

function H.write_file(path, text)
  local fd = assert(io.open(path, "wb"))
  fd:write(text or "")
  fd:close()
  return path
end

function H.first_thread_id(query)
  local out = H.system({ "notmuch", "search", query or "tag:inbox" })
  local id = out:match("thread:([0-9A-Za-z]+)")
  H.ok(id, "could not parse a thread id from notmuch search output: " .. out)
  return id
end

return H
