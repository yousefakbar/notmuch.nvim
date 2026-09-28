local M = {}

local Parser = {}
Parser.__index = Parser

local function whitespace(char)
  return char == " " or char == "\n" or char == "\r" or char == "\t"
end

function M.new()
  return setmetatable({
    input = "",
    pos = 1,
    started = false,
    closed = false,
    expect = "value_or_end",
    depth = 0,
    in_string = false,
    escaped = false,
    object = nil,
    error = nil,
  }, Parser)
end

function Parser:feed(chunk)
  if self.error or self.closed and chunk:find("%S") then
    self.error = self.error or "Unexpected data after search JSON array"
    return
  end
  if self.pos > 1 then
    self.input = self.input:sub(self.pos) .. chunk
    self.pos = 1
  else
    self.input = self.input .. chunk
  end
end

---Consume a bounded amount of input and return complete top-level objects.
function Parser:drain(max_records, max_bytes)
  local records = {}
  local processed = 0
  local segment = self.object and self.pos or nil

  while
    not self.error
    and self.pos <= #self.input
    and #records < max_records
    and processed < max_bytes
  do
    local char = self.input:sub(self.pos, self.pos)
    local at = self.pos
    self.pos = self.pos + 1
    processed = processed + 1

    if self.object then
      if self.in_string then
        if self.escaped then
          self.escaped = false
        elseif char == "\\" then
          self.escaped = true
        elseif char == '"' then
          self.in_string = false
        end
      elseif char == '"' then
        self.in_string = true
      elseif char == "{" or char == "[" then
        self.depth = self.depth + 1
      elseif char == "}" or char == "]" then
        self.depth = self.depth - 1
        if self.depth == 0 then
          self.object[#self.object + 1] = self.input:sub(segment, at)
          records[#records + 1] = table.concat(self.object)
          self.object = nil
          segment = nil
          self.expect = "comma_or_end"
        end
      end
    elseif not self.started then
      if char == "[" then
        self.started = true
      elseif not whitespace(char) then
        self.error = "Search JSON must be an array"
      end
    elseif self.closed then
      if not whitespace(char) then
        self.error = "Unexpected data after search JSON array"
      end
    elseif self.expect == "value_or_end" or self.expect == "value" then
      if char == "{" then
        self.object = {}
        self.depth = 1
        self.in_string, self.escaped = false, false
        segment = at
      elseif char == "]" and self.expect == "value_or_end" then
        self.closed = true
      elseif not whitespace(char) then
        self.error = "Expected a search record or closing bracket"
      end
    elseif self.expect == "comma_or_end" then
      if char == "," then
        self.expect = "value"
      elseif char == "]" then
        self.closed = true
      elseif not whitespace(char) then
        self.error = "Expected a comma or closing bracket"
      end
    end
  end

  if self.object and segment then
    self.object[#self.object + 1] = self.input:sub(segment, self.pos - 1)
  end
  if self.pos > #self.input then
    self.input, self.pos = "", 1
  elseif self.pos > 65536 then
    self.input, self.pos = self.input:sub(self.pos), 1
  end
  return records, self.error
end

function Parser:has_input()
  return self.pos <= #self.input
end

function Parser:finish()
  if self.error then
    return nil, self.error
  end
  if not self.started or not self.closed or self.object then
    return nil, "Truncated search JSON"
  end
  return true
end

return M
