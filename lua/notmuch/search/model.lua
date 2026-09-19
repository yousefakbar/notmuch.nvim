local M = {}

---Decode without discarding positional nulls (notably the query pair).
function M.decode(text)
  local ok, records = pcall(vim.json.decode, text)

  -- Check that json decoding worked successfully
  if not ok then
    return nil, "Invalid search JSON: " .. tostring(records)
  end

  -- Check that object is a json array
  if type(records) ~= "table" or not vim.islist(records) or not text:match("^%s*%[") then
    return nil, "Search JSON must be an array"
  end

  -- Go through each record in the json array and validate the structure
  local seen = {}
  for i, record in ipairs(records) do
    -- Common helper function to return with error msg
    local function invalid(field)
      return nil, ("Invalid search record %d (%s)"):format(i, field)
    end

    -- Ensure each record is a table of fields (author, subject, thread, etc.)
    if type(record) ~= "table" then
      return invalid("object")
    end

    -- Ensure thread ID format (*unique* 16-character alphanumberic combination)
    if
      type(record.thread) ~= "string"
      or not record.thread:match("^[0-9a-fA-F]+$")
      or seen[record.thread]
    then
      return invalid("thread ID")
    end

    -- Mark as seen to track unique and reject duplicates
    seen[record.thread] = true

    -- Validate "matched" and "total" numberic values
    for _, field in ipairs({ "matched", "total" }) do
      local n = record[field]
      if type(n) ~= "number" or n < 0 or n == math.huge or n ~= math.floor(n) then
        return invalid(field)
      end
    end

    -- Validate string fields
    for _, field in ipairs({ "authors", "subject", "date_relative" }) do
      if record[field] == nil or record[field] == vim.NIL then
        record[field] = ""
      end
      if type(record[field]) ~= "string" then
        return invalid(field)
      end
    end

    -- Normalize NULL timestamp
    if record.timestamp == nil or record.timestamp == vim.NIL then
      record.timestamp = 0
    end

    -- Validate timestamp format and value (decimal and not huge)
    if
      type(record.timestamp) ~= "number"
      or math.abs(record.timestamp) == math.huge
      or record.timestamp ~= math.floor(record.timestamp)
    then
      return invalid("timestamp")
    end

    -- Ensure tags is a table list of strings
    if type(record.tags) ~= "table" or not vim.islist(record.tags) then
      return invalid("tags")
    end
    for _, tag in ipairs(record.tags) do
      if type(tag) ~= "string" then
        return invalid("tag")
      end
    end
  end

  return records
end

return M
