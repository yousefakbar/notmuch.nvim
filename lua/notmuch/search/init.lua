local M = {}
local api = vim.api
local states = {}
local render = require("notmuch.search.render")
local highlights = require("notmuch.search.highlights")
local namespace = highlights.namespace
local initialized = false

local function buffer(buf)
  return (not buf or buf == 0) and api.nvim_get_current_buf() or buf
end

function M.get_state(buf)
  return states[buffer(buf)]
end

function M.get_record(buf, line)
  buf = buffer(buf)
  local state = states[buf]
  if not state then
    return nil
  end
  line = line or api.nvim_win_get_cursor(0)[1]
  return state.records[state.rows[line]]
end

function M.selected(buf, first, last)
  buf = buffer(buf)
  first = first or api.nvim_win_get_cursor(0)[1]
  last = last or first
  local records = {}
  for line = math.min(first, last), math.max(first, last) do
    local record = M.get_record(buf, line)
    if record then
      records[#records + 1] = record
    end
  end
  return records
end

local function windows(buf)
  local wins = {}
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf then
      wins[#wins + 1] = win
    end
  end
  return wins
end

local function layout_width(buf, state)
  local width
  for _, win in ipairs(windows(buf)) do
    local info = vim.fn.getwininfo(win)[1]
    local size = api.nvim_win_get_width(win) - (info and info.textoff or 0)
    width = math.min(width or size, size)
  end
  return math.max(1, width or state.width or 100)
end

local function selections(buf, state)
  local out = {}
  for _, win in ipairs(windows(buf)) do
    local cursor = api.nvim_win_get_cursor(win)
    local record = M.get_record(buf, cursor[1])
    out[win] = {
      id = record and record.thread,
      index = state.rows[cursor[1]],
      row = cursor[1],
      col = cursor[2],
      view = api.nvim_win_call(win, vim.fn.winsaveview),
    }
  end
  return out
end

function M.draw(buf, saved, reset_widths)
  buf = buffer(buf)
  local state = states[buf]
  if not state or not api.nvim_buf_is_valid(buf) then
    return
  end
  saved = saved or selections(buf, state)
  local opts = require("notmuch.config").options.search
  local width = layout_width(buf, state)
  if reset_widths or width ~= state.width then
    state.widths = nil
  end
  local result = render.render(state.records, opts, width, state.widths)
  state.width, state.widths = width, result.widths
  local status = ({
    loading = "Searching…",
    refreshing = "Refreshing…",
    error = "Search failed",
  })[state.status] or (#state.records .. " threads")
  if state.stale then
    status = status .. " (stale)"
  end
  local hints =
    "Hints: <Enter>: Open | K: Details | r: Refresh | o: Reverse | +/-/=: Tags | dd: Delete | a: Archive | A: Archive+read | %: Sync | q: Close"
  local lines = { status .. " — " .. hints }
  vim.list_extend(lines, result.lines)
  if #state.records == 0 then
    lines[#lines + 1] = state.error and ("Search failed: " .. render.clean(state.error):sub(1, 200))
      or (state.status == "loading" and "Searching…" or "No matching threads")
  end
  state.rows, state.id_to_row = {}, {}
  for row, index in pairs(result.rows) do
    state.rows[row + 1] = index
    state.id_to_row[state.records[index].thread] = row + 1
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  api.nvim_buf_set_extmark(
    buf,
    namespace,
    0,
    0,
    { end_col = #lines[1], hl_group = "NotmuchSearchHint" }
  )
  api.nvim_buf_set_extmark(buf, namespace, 0, 0, {
    end_col = #status,
    hl_group = state.error and "NotmuchSearchError" or "NotmuchSearchStatus",
    priority = 110,
  })
  for _, key in ipairs({ "<Enter>", "K", "r", "o", "+/-/=", "dd", "a", "A", "%", "q" }) do
    local start = lines[1]:find(key .. ":", #status + 1, true)
    if start then
      api.nvim_buf_set_extmark(buf, namespace, 0, start - 1, {
        end_col = start - 1 + #key,
        hl_group = "NotmuchSearchHintKey",
        priority = 110,
      })
    end
  end
  for _, span in ipairs(result.highlights) do
    api.nvim_buf_set_extmark(buf, namespace, span.row + 1, span.start_col, {
      end_col = span.end_col,
      hl_group = span.group,
    })
  end
  if #state.records == 0 then
    api.nvim_buf_set_extmark(buf, namespace, #lines - 1, 0, {
      end_col = #lines[#lines],
      hl_group = state.error and "NotmuchSearchError" or "NotmuchSearchStatus",
    })
  end
  vim.b[buf].notmuch_search_query = state.query
  vim.b[buf].notmuch_search_status = state.status
  vim.b[buf].notmuch_search_count = #state.records
  local first_row = opts.show_header and 3 or 2
  for win, selection in pairs(saved) do
    if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
      local row = selection.id and state.id_to_row[selection.id]
      if not row and selection.index and #state.records > 0 then
        row = first_row + math.min(selection.index, #state.records) - 1
      end
      row = math.min(row or selection.row, #lines)
      api.nvim_win_call(win, function()
        local view = selection.view
        view.lnum, view.col = row, math.min(selection.col, #lines[row])
        vim.fn.winrestview(view)
      end)
    end
  end
end

function M.cancel(buf)
  local state = states[buffer(buf)]
  if not state then
    return
  end
  state.generation = state.generation + 1
  if state.process then
    pcall(state.process.kill, state.process, 15)
  end
  state.process = nil
end

---Invalidate an in-flight snapshot before changing records or the database.
function M.before_mutation(buf)
  local state = states[buffer(buf)]
  if not state then
    return
  end
  M.cancel(buf)
  state.status, state.error = "ready", nil
end

function M.refresh(buf, target)
  buf = buffer(buf)
  local state = states[buf]
  if not state then
    return
  end
  M.cancel(buf)
  local generation = state.generation
  local initial = not state.loaded
  local origin_win = api.nvim_get_current_win()
  state.status, state.error = initial and "loading" or "refreshing", nil
  M.draw(buf)
  state.process = require("notmuch.async").run_notmuch_search(state.query, function(result)
    if states[buf] ~= state or generation ~= state.generation or not api.nvim_buf_is_valid(buf) then
      return
    end
    state.process = nil
    local records, err
    if result.code == 0 then
      records, err = require("notmuch.search.model").decode(result.stdout or "")
    else
      err = ("notmuch search exited %s: %s"):format(
        tostring(result.code),
        (result.stderr or ""):sub(1, 2000)
      )
    end
    local saved = selections(buf, state)
    if not records then
      state.status, state.error, state.stale = "error", err, state.loaded or false
      M.draw(buf, saved)
      vim.notify("notmuch.nvim: " .. err, vim.log.levels.ERROR)
      return
    end
    if state.reversed then
      local reversed = {}
      for i = #records, 1, -1 do
        reversed[#reversed + 1] = records[i]
      end
      records = reversed
    end
    state.records, state.loaded, state.stale, state.status = records, true, false, "ready"
    M.draw(buf, saved, true)
    if
      initial
      and api.nvim_get_current_win() == origin_win
      and api.nvim_win_get_buf(origin_win) == buf
      and #records > 0
    then
      local row = api.nvim_win_get_cursor(origin_win)[1]
      if row <= 3 or target then
        api.nvim_win_set_cursor(
          origin_win,
          { state.id_to_row[target or records[1].thread] or state.id_to_row[records[1].thread], 0 }
        )
      end
    end
  end)
end

local function setup()
  if initialized then
    return
  end
  initialized = true
  highlights.setup()
  local group = api.nvim_create_augroup("NotmuchSearch", { clear = true })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      M.cancel(ev.buf)
      states[ev.buf] = nil
    end,
  })
  local pending = false
  api.nvim_create_autocmd({ "VimResized", "WinResized", "BufWinEnter", "WinClosed" }, {
    group = group,
    callback = function()
      if pending then
        return
      end
      pending = true
      vim.defer_fn(function()
        pending = false
        for buf, state in pairs(states) do
          if api.nvim_buf_is_valid(buf) and layout_width(buf, state) ~= state.width then
            M.draw(buf, nil, true)
          end
        end
      end, 100)
    end,
  })
end

---Create a structured buffer. Also useful for fixtures without subprocesses.
function M.create(query, records)
  setup()
  local buf = api.nvim_create_buf(true, true)
  api.nvim_buf_set_name(buf, "notmuch-search: " .. query)
  states[buf] = {
    query = query,
    records = records or {},
    rows = {},
    generation = 0,
    reversed = false,
    status = records and "ready" or "loading",
    loaded = records ~= nil,
  }
  api.nvim_win_set_buf(0, buf)
  vim.bo[buf].filetype = "notmuch-threads"
  vim.bo[buf].bufhidden = "hide"
  M.draw(buf)
  return buf
end

function M.open(query, target)
  for buf, state in pairs(states) do
    if state.query == query and api.nvim_buf_is_valid(buf) then
      api.nvim_win_set_buf(0, buf)
      M.draw(buf)
      return true
    end
  end
  local buf = M.create(query)
  M.refresh(buf, target)
end

function M.reverse(buf)
  buf = buffer(buf)
  local state = states[buf]
  if not state then
    return
  end
  local saved = selections(buf, state)
  local records = {}
  for i = #state.records, 1, -1 do
    records[#records + 1] = state.records[i]
  end
  state.records, state.reversed = records, not state.reversed
  M.draw(buf, saved)
end

function M.remove(buf, ids)
  buf = buffer(buf)
  local state = states[buf]
  if not state then
    return
  end
  local saved = selections(buf, state)
  local kept = {}
  for _, record in ipairs(state.records) do
    if not ids[record.thread] then
      kept[#kept + 1] = record
    end
  end
  state.records = kept
  M.draw(buf, saved)
end

function M.details()
  local record = M.get_record(0)
  if not record then
    return
  end
  local lines = {
    "Thread: " .. record.thread,
    "Date: " .. record.date_relative .. " (" .. record.timestamp .. ")",
    ("Messages: %d matched / %d total"):format(record.matched, record.total),
    "Authors: " .. record.authors,
    "Subject: " .. record.subject,
    "Tags: " .. table.concat(record.tags, " "),
  }
  for i, line in ipairs(lines) do
    lines[i] = render.clean(line)
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable, vim.bo[buf].bufhidden = false, "wipe"
  local width = math.max(1, math.min(100, vim.o.columns - 4))
  local height = 0
  for _, line in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  height = math.max(1, math.min(height, vim.o.lines - 6))
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = "rounded",
    style = "minimal",
    title = " Thread details ",
  })
  vim.wo[win].wrap = true
  vim.keymap.set("n", "q", function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end, { buffer = buf })
end

return M
