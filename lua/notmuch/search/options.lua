local M = {}

M.fields = {
  date = "Date",
  timestamp = "Timestamp",
  count = "Msgs",
  matched = "Matched",
  total = "Total",
  authors = "Authors",
  subject = "Subject",
  tags = "Tags",
  thread = "Thread",
}

function M.defaults()
  return {
    show_header = true,
    separator = "  ",
    columns = {
      { field = "date", label = "Date", width = 12 },
      { field = "count", label = "Msgs", width = 7, align = "right" },
      { field = "authors", label = "Authors", width = 24 },
      { field = "subject", label = "Subject", width = "fill", min_width = 20 },
      { field = "tags", label = "Tags", width = 30 },
    },
  }
end

local function printable(s)
  return type(s) == "string" and not s:find("[%z\1-\31\127]")
end

local function positive(n)
  return type(n) == "number" and n > 0 and n < math.huge and n == math.floor(n)
end

-- One validation attempt. Never recurse through the public fallback path.
local function normalize_once(options)
  return pcall(function()
    assert(options == nil or type(options) == "table", "search must be a table")
    local opts = vim.tbl_deep_extend("force", M.defaults(), options or {})
    if options and options.columns ~= nil then
      opts.columns = vim.deepcopy(options.columns)
    end
    assert(type(opts.show_header) == "boolean", "show_header must be boolean")
    assert(printable(opts.separator), "separator must be printable single-line text")
    assert(
      type(opts.columns) == "table" and vim.islist(opts.columns) and #opts.columns > 0,
      "columns must be a non-empty list"
    )
    local seen, fill = {}, false
    for _, col in ipairs(opts.columns) do
      assert(type(col) == "table" and M.fields[col.field], "unknown column field")
      assert(not seen[col.field], "duplicate field: " .. col.field)
      seen[col.field] = true
      col.label = col.label or M.fields[col.field]
      col.align = col.align or "left"
      col.width = col.width or "auto"
      col.min_width = col.min_width or 1
      assert(printable(col.label), "label must be printable single-line text")
      assert(
        col.highlight == nil or (printable(col.highlight) and col.highlight ~= ""),
        "invalid highlight group"
      )
      assert(
        col.align == "left" or col.align == "right" or col.align == "center",
        "invalid alignment"
      )
      assert(positive(col.width) or col.width == "auto" or col.width == "fill", "invalid width")
      assert(positive(col.min_width), "invalid min_width")
      assert(
        col.max_width == nil or (positive(col.max_width) and col.max_width >= col.min_width),
        "invalid max_width"
      )
      if col.width == "fill" then
        assert(not fill, "only one fill column is allowed")
        fill = true
      end
    end
    return opts
  end)
end

---Validate as a unit and emit at most one warning per call, even if defaults are broken.
function M.normalize(options)
  local ok, result = normalize_once(options)
  if ok then
    return result
  end

  local defaults_ok, fallback = normalize_once(nil)
  local message = "notmuch.nvim: invalid search layout: " .. tostring(result)
  if defaults_ok then
    message = message .. "; using defaults"
  else
    -- Keep this already-normalized emergency layout independent of M.defaults().
    -- A typo in the source defaults must not recurse or leave setup unusable.
    fallback = {
      show_header = true,
      separator = "  ",
      columns = {
        { field = "subject", label = "Subject", width = "fill", min_width = 1, align = "left" },
      },
    }
    message = message .. "; built-in defaults are also invalid; using a minimal subject-only layout"
  end
  vim.notify(message, vim.log.levels.WARN)
  return fallback
end

return M
