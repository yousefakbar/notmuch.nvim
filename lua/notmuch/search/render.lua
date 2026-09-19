local M = {}
local displaywidth = vim.fn.strdisplaywidth

function M.clean(text)
  return tostring(text):gsub("[%z\1-\31\127]", " ")
end

local groups = {
  date = "Date",
  timestamp = "Date",
  count = "Count",
  matched = "Count",
  total = "Count",
  authors = "Authors",
  subject = "Subject",
  tags = "Tags",
  thread = "Thread",
}

local function segments(record, col)
  local field = col.field
  local group = col.highlight or ("NotmuchSearch" .. groups[field])
  local value = record[field]
  if field == "date" then
    value = record.date_relative
  end
  if field == "count" then
    value = ("[%d/%d]"):format(record.matched, record.total)
  end
  if field == "subject" and value == "" then
    value = "(no subject)"
  end
  if field == "authors" and value == "" then
    value = "(unknown)"
  end
  if field == "tags" then
    local out = {}
    for i, tag in ipairs(record.tags) do
      if i > 1 then
        out[#out + 1] = { text = " " }
      end
      out[#out + 1] = { text = M.clean(tag), group = group }
    end
    return out
  end
  value = M.clean(value or "")
  if field == "authors" and not col.highlight then
    local boundary = value:find("|", 1, true)
    if boundary then
      return {
        { text = value:sub(1, boundary), group = group },
        { text = value:sub(boundary + 1), group = "NotmuchSearchAuthorsOther" },
      }
    end
  end
  return { { text = value, group = group } }
end

local function joined(parts)
  local out = {}
  for _, part in ipairs(parts) do
    out[#out + 1] = part.text
  end
  return table.concat(out)
end

---Return a prefix in whole characters, keeping composing characters with bases.
local function prefix(text, cells)
  if cells <= 0 then
    return ""
  end
  local lo, hi = 0, vim.fn.strchars(text, true)
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if displaywidth(vim.fn.strcharpart(text, 0, mid, true)) <= cells then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return vim.fn.strcharpart(text, 0, lo, true)
end

local function cell(parts, width, align)
  local text = joined(parts)
  local clipped = displaywidth(text) > width
  local visible = clipped and prefix(text, width - displaywidth("…")) or text
  local suffix = clipped and "…" or ""
  local padding = math.max(0, width - displaywidth(visible .. suffix))
  local left = align == "right" and padding or (align == "center" and math.floor(padding / 2) or 0)
  local spans, offset = {}, 0
  for _, part in ipairs(parts) do
    local finish = math.min(#visible, offset + #part.text)
    if part.group and finish > offset then
      spans[#spans + 1] = { start_col = left + offset, end_col = left + finish, group = part.group }
    end
    offset = offset + #part.text
  end
  if clipped then
    spans[#spans + 1] = {
      start_col = left + #visible,
      end_col = left + #visible + #suffix,
      group = "NotmuchSearchStatus",
    }
  end
  return string.rep(" ", left) .. visible .. suffix .. string.rep(" ", padding - left), spans
end

---Pure rendering; cached widths keep auto columns steady during tag mutations.
function M.render(records, opts, available, cached_widths)
  local widths = cached_widths and vim.deepcopy(cached_widths) or {}
  if not cached_widths then
    local used, fill = math.max(0, #opts.columns - 1) * displaywidth(opts.separator), nil
    for i, col in ipairs(opts.columns) do
      local width
      if type(col.width) == "number" then
        width = col.width
      elseif col.width == "fill" then
        fill = i
      else
        width = opts.show_header and displaywidth(col.label) or 0
        for _, record in ipairs(records) do
          width = math.max(width, displaywidth(joined(segments(record, col))))
        end
        width = math.max(col.min_width, math.min(width, col.max_width or math.huge))
      end
      if width then
        widths[i], used = width, used + width
      end
    end
    if fill then
      local col = opts.columns[fill]
      widths[fill] = math.max(col.min_width, math.min(available - used, col.max_width or math.huge))
    end
  end
  local lines, highlights, rows = {}, {}, {}
  local function row(record)
    local chunks, bytes = {}, 0
    for i, col in ipairs(opts.columns) do
      if i > 1 then
        chunks[#chunks + 1] = opts.separator
        bytes = bytes + #opts.separator
      end
      local parts = record and segments(record, col)
        or { { text = col.label, group = "NotmuchSearchHeader" } }
      local text, spans = cell(parts, widths[i], col.align)
      for _, span in ipairs(spans) do
        span.row = #lines
        span.start_col, span.end_col = span.start_col + bytes, span.end_col + bytes
        highlights[#highlights + 1] = span
      end
      chunks[#chunks + 1], bytes = text, bytes + #text
    end
    lines[#lines + 1] = table.concat(chunks)
  end
  if opts.show_header then
    row(nil)
  end
  for i, record in ipairs(records) do
    row(record)
    rows[#lines] = i
  end
  return { lines = lines, highlights = highlights, rows = rows, widths = widths }
end

return M
