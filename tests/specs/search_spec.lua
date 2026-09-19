local H = dofile("tests/helpers.lua")
local options = require("notmuch.search.options")
local renderer = require("notmuch.search.render")
local model = require("notmuch.search.model")
local search = require("notmuch.search")

local function record(id, subject)
  return {
    thread = id or "abc",
    timestamp = 1789640687,
    date_relative = "Yest. 13:24",
    matched = 1,
    total = 2,
    authors = "Alice | Bob",
    subject = subject or "Test subject",
    tags = { "inbox", "unread" },
    query = { "id:test", vim.NIL },
  }
end

local function mock_requests(fn)
  local async = require("notmuch.async")
  local old, notify = async.run_notmuch_search, vim.notify
  local requests, notes = {}, {}
  async.run_notmuch_search = function(query, cb)
    local request = { query = query, complete = cb }
    requests[#requests + 1] = request
    return {
      kill = function()
        request.killed = true
      end,
    }
  end
  vim.notify = function(msg)
    notes[#notes + 1] = msg
  end
  local ok, err = xpcall(function()
    fn(requests, notes)
  end, debug.traceback)
  async.run_notmuch_search, vim.notify = old, notify
  if not ok then
    error(err)
  end
end

local function finish(request, records)
  request.complete({ code = 0, stdout = vim.json.encode(records) })
end

return {
  {
    name = "search shares narrow-window layout without refetching and preserves colorscheme overrides",
    run = function()
      mock_requests(function(requests)
        local buf = H.search_fixture({ "a", "b" })
        local original_win = vim.api.nvim_get_current_win()
        local ok, err = pcall(function()
          vim.api.nvim_win_set_cursor(0, { 4, 0 })
          vim.cmd("vsplit")
          local narrow = vim.api.nvim_get_current_win()
          vim.api.nvim_win_set_width(narrow, 30)
          search.draw(buf, nil, true)
          H.ok(search.get_state(buf).width <= 30)
          H.eq("b", search.get_record(buf).thread)
          H.eq(0, #requests)
          vim.api.nvim_set_hl(0, "NotmuchSearchAuthors", { link = "Function" })
          vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
          H.eq("Function", vim.api.nvim_get_hl(0, { name = "NotmuchSearchAuthors" }).link)
          vim.api.nvim_win_close(narrow, true)
          vim.api.nvim_set_current_win(original_win)
        end)
        vim.api.nvim_buf_delete(buf, { force = true })
        if not ok then
          error(err)
        end
      end)
    end,
  },
  {
    name = "search model validates arrays, preserves nulls, and handles bad data",
    run = function()
      local decoded = assert(model.decode(vim.json.encode({ record() })))
      H.eq(vim.NIL, decoded[1].query[2])
      H.same({}, assert(model.decode("[]")))
      for _, json in ipairs({ "{}", "null", "[", '[{"thread":"bad query"}]', "[false]" }) do
        local value, err = model.decode(json)
        H.eq(nil, value)
        H.ok(err)
      end
      local invalid = record()
      invalid.tags = { 42 }
      H.eq(nil, model.decode(vim.json.encode({ invalid })))
      H.eq(nil, model.decode(vim.json.encode({ record(), record() })))
      local missing = record()
      missing.subject, missing.authors = nil, vim.NIL
      local value = assert(model.decode(vim.json.encode({ missing })))
      H.eq("", value[1].subject)
      H.eq("", value[1].authors)
    end,
  },
  {
    name = "search columns replace defaults and validation does not mutate options",
    run = function()
      local input = { columns = { { field = "subject", width = "fill" } }, show_header = false }
      local before = vim.deepcopy(input)
      local opts = options.normalize(input)
      H.eq(1, #opts.columns)
      H.eq("Subject", opts.columns[1].label)
      H.same(before, input)
      local old, notes = vim.notify, {}
      vim.notify = function(msg)
        notes[#notes + 1] = msg
      end
      for _, value in ipairs({
        { columns = {} },
        { columns = { { field = "subject", width = 0 } } },
        { columns = { { field = "subject" }, { field = "subject" } } },
        { columns = { { field = "subject", width = "fill" }, { field = "tags", width = "fill" } } },
        { separator = "\n" },
      }) do
        H.eq(5, #options.normalize(value).columns)
      end
      vim.notify = old
      H.eq(5, #notes)
    end,
  },
  {
    name = "search invalid user layouts warn once and recover to valid defaults",
    run = function()
      local old_notify = vim.notify
      local notes = {}
      vim.notify = function(message)
        notes[#notes + 1] = message
        assert(#notes <= 1, "unexpected repeated fallback warning")
      end
      local ok, err = xpcall(function()
        for _, invalid in ipairs({ "field", "fill" }) do
          local input = options.defaults()
          if invalid == "field" then
            input.columns[3].field = "authorss"
          else
            input.columns[5].width = "fill"
          end
          notes = {}
          local normalized = options.normalize(input)
          H.eq(1, #notes)
          H.contains(notes[1], "using defaults")
          H.eq("authors", normalized.columns[3].field)
          H.eq("fill", normalized.columns[4].width)
          H.eq("number", type(normalized.columns[5].width))
          H.eq(2, #renderer.render({ record() }, normalized, 120).lines)
        end
      end, debug.traceback)
      vim.notify = old_notify
      if not ok then
        error(err)
      end
    end,
  },
  {
    name = "search broken built-in defaults use a bounded renderable emergency fallback",
    run = function()
      local old_defaults, old_notify = options.defaults, vim.notify
      local notes, calls
      vim.notify = function(message)
        notes[#notes + 1] = message
        assert(#notes <= 1, "recursive fallback warning")
      end
      local ok, err = xpcall(function()
        for _, invalid in ipairs({ "field", "fill" }) do
          options.defaults = function()
            calls = calls + 1
            local defaults = old_defaults()
            if invalid == "field" then
              defaults.columns[3].field = "authorss"
            else
              defaults.columns[5].width = "fill"
            end
            return defaults
          end
          -- Repeated calls each warn once; no global suppression hides the error.
          for _ = 1, 2 do
            notes, calls = {}, 0
            local normalized = options.normalize(nil)
            H.eq(2, calls)
            H.eq(1, #notes)
            H.contains(notes[1], "built-in defaults are also invalid")
            H.eq(1, #normalized.columns)
            H.eq("subject", normalized.columns[1].field)
            H.eq("left", normalized.columns[1].align)
            H.eq(2, #renderer.render({ record() }, normalized, 80).lines)
          end
        end
      end, debug.traceback)
      options.defaults, vim.notify = old_defaults, old_notify
      if not ok then
        error(err)
      end
    end,
  },
  {
    name = "search renderer measures Unicode cells but highlights byte columns",
    run = function()
      local opts = options.normalize({
        show_header = false,
        separator = " | ",
        columns = {
          { field = "subject", width = 6 },
          { field = "count", width = 8, align = "right" },
        },
      })
      local data = renderer.render(
        { record("a", "你好世界"), record("b", "é test"), record("c", "📨 hello") },
        opts,
        80
      )
      for _, line in ipairs(data.lines) do
        H.eq(17, vim.fn.strdisplaywidth(line))
      end
      H.contains(data.lines[1], "你好… ")
      H.eq(1, data.rows[1])
      local count
      for _, span in ipairs(data.highlights) do
        local line = data.lines[span.row + 1]
        H.ok(span.end_col <= #line)
        if span.row == 0 and span.group == "NotmuchSearchCount" then
          count = span
        end
      end
      H.ok(count)
      H.eq("[1/2]", data.lines[1]:sub(count.start_col + 1, count.end_col))
    end,
  },
  {
    name = "search widths, control sanitation, author spans, and per-column overrides",
    run = function()
      local opts = options.normalize({
        separator = " ",
        columns = {
          { field = "count", width = "auto", max_width = 7 },
          { field = "authors", width = 20 },
          { field = "subject", width = "fill", min_width = 3 },
        },
      })
      local data = renderer.render({ record("a", "a\nb\t\27c") }, opts, 40)
      H.eq(40, vim.fn.strdisplaywidth(data.lines[2]))
      H.eq(1, data.rows[2])
      H.eq(nil, data.rows[1])
      H.contains(data.lines[2], "a b  c")
      local other = false
      for _, span in ipairs(data.highlights) do
        if span.group == "NotmuchSearchAuthorsOther" then
          other = true
        end
      end
      H.eq(true, other)
      opts.columns[2].highlight = "DiagnosticWarn"
      local narrow = renderer.render({ record() }, opts, 5)
      H.eq(3, narrow.widths[3])
      for _, span in ipairs(narrow.highlights) do
        H.ok(span.group ~= "NotmuchSearchAuthorsOther")
      end
      local center = renderer.render(
        { record("a", "x") },
        options.normalize({
          show_header = false,
          columns = { { field = "subject", width = 4, align = "center" } },
        }),
        20
      )
      H.eq(" x  ", center.lines[1])
    end,
  },
  {
    name = "search refresh discards superseded callbacks and preserves selection and mappings",
    run = function()
      mock_requests(function(requests)
        local buf = H.search_fixture({ "a", "b" })
        local state = search.get_state(buf)
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        vim.keymap.set("n", "DD", function() end, { buffer = buf })
        search.refresh(buf)
        search.refresh(buf)
        H.eq(true, requests[1].killed)
        finish(requests[1], { record("c") })
        H.eq("refreshing", state.status)
        finish(requests[2], { record("b"), record("a") })
        H.eq(buf, vim.api.nvim_get_current_buf())
        H.eq("b", search.get_record(buf).thread)
        H.eq(3, vim.api.nvim_win_get_cursor(0)[1])
        H.ok(vim.fn.maparg("DD", "n", false, true).buffer == 1)
        search.reverse(buf)
        H.eq("b", search.get_record(buf).thread)
        search.refresh(buf)
        finish(requests[3], { record("b"), record("a") })
        H.eq("a", state.records[1].thread)
        H.eq("b", search.get_record(buf).thread)
        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end,
  },
  {
    name = "search errors retain stale results and buffer wipe cancels immediately",
    run = function()
      mock_requests(function(requests, notes)
        local buf = H.search_fixture({ "a" })
        search.refresh(buf)
        requests[1].complete({ code = 1, stderr = "bad database" })
        H.eq(true, search.get_state(buf).stale)
        H.eq("a", search.get_record(buf, 3).thread)
        H.contains(notes[1], "bad database")
        search.refresh(buf)
        vim.api.nvim_buf_delete(buf, { force = true })
        H.eq(true, requests[2].killed)
        finish(requests[2], { record("b") })
        H.eq(nil, search.get_state(buf))
      end)
    end,
  },
  {
    name = "search completion does not move unrelated buffers or focus",
    run = function()
      mock_requests(function(requests)
        local buf = search.create("focus-test-" .. vim.uv.hrtime())
        search.refresh(buf)
        local other = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, other)
        finish(requests[1], { record() })
        H.eq(other, vim.api.nvim_get_current_buf())
        H.eq("ready", search.get_state(buf).status)
        vim.api.nvim_buf_delete(buf, { force = true })
        vim.api.nvim_buf_delete(other, { force = true })
      end)
    end,
  },
  {
    name = "search mutation invalidates pending snapshots; missing selection uses nearest result",
    run = function()
      mock_requests(function(requests)
        local buf = H.search_fixture({ "a", "b", "c" })
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        search.refresh(buf)
        search.before_mutation(buf)
        search.remove(buf, { b = true })
        finish(requests[1], { record("b") })
        H.eq("c", search.get_record(buf).thread)
        H.eq(2, #search.get_state(buf).records)
        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end,
  },
  {
    name = "search subject-only layout keeps IDs usable, header inert, and details complete",
    run = function()
      local config = require("notmuch.config")
      local old = config.options.search
      config.options.search =
        options.normalize({ show_header = false, columns = { { field = "subject", width = 3 } } })
      local buf = H.search_fixture({ "abcdef" })
      local ok, err = pcall(function()
        H.eq(nil, search.get_record(buf, 1))
        H.eq("abcdef", search.get_record(buf, 2).thread)
        H.ok(not table.concat(H.current_lines(), "\n"):find("abcdef", 1, true))
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        search.details()
        H.contains(H.current_lines(), "Subject: Subject abcdef")
        H.eq(false, vim.bo.modifiable)
        vim.api.nvim_win_close(0, true)
        H.eq(buf, vim.api.nvim_get_current_buf())
        config.options.search = old
        search.draw(buf, nil, true)
        H.eq("abcdef", search.get_record(buf).thread)
        H.eq(nil, search.get_record(buf, 2))
      end)
      config.options.search = old
      vim.api.nvim_buf_delete(buf, { force = true })
      if not ok then
        error(err)
      end
    end,
  },
}
