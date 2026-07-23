local H = dofile("tests/helpers.lua")

local function fake_thread(initial_tags)
  local t = { added = {}, removed = {}, tags = vim.deepcopy(initial_tags or {}) }
  function t:add_tag(tag)
    self.added[#self.added + 1] = tag
    self.tags[tag] = true
  end
  function t:rm_tag(tag)
    self.removed[#self.removed + 1] = tag
    self.tags[tag] = nil
  end
  function t:get_tags()
    return self.tags
  end
  return t
end

local function with_mock_cnotmuch(state, fn)
  local old_loaded = package.loaded["notmuch.cnotmuch"]
  package.loaded["notmuch.cnotmuch"] = function(_, mode)
    local db
    db = {
      mode = mode,
      create_query = function(query)
        state.queries[#state.queries + 1] = query
        local id = query:match("^thread:(.+)$")
        return {
          get_threads = function()
            return state.threads[id] and { state.threads[id] } or {}
          end,
        }
      end,
      close = function()
        state.closed = state.closed + 1
      end,
    }
    state.dbs[#state.dbs + 1] = db
    return db
  end

  local ok, err = pcall(fn)
  package.loaded["notmuch.cnotmuch"] = old_loaded
  if not ok then
    error(err, 0)
  end
end

local function map_callback(lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
    if map.lhs == lhs then
      return map.callback
    end
  end
end

local function silence_print(fn)
  local old_print = print
  print = function() end
  local ok, err = pcall(fn)
  print = old_print
  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "delete DelThread adds del, removes inbox, deletes current line, and restores modifiable",
    run = function()
      local t1 = fake_thread({ inbox = true })
      local state = { threads = { abc = t1 }, queries = {}, dbs = {}, closed = 0 }
      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "Hints: delete",
        "thread:abc  today [1/1] subject",
        "thread:def  today [1/1] other",
      })
      vim.bo.filetype = "notmuch-threads"
      vim.cmd("runtime ftplugin/notmuch-threads.lua")
      vim.bo.modifiable = false

      with_mock_cnotmuch(state, function()
        silence_print(function()
          vim.cmd("2DelThread")
        end)
      end)

      H.same({ "del" }, t1.added)
      H.same({ "inbox" }, t1.removed)
      H.same(
        { "Hints: delete", "thread:def  today [1/1] other" },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
      H.eq(false, vim.bo.modifiable)
      H.same({ "thread:abc", "thread:abc" }, state.queries)
      H.eq(2, state.closed)

      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "delete DelThread works for ranges and removes selected lines",
    run = function()
      local t1 = fake_thread({ inbox = true })
      local t2 = fake_thread({ inbox = true })
      local state = { threads = { abc = t1, def = t2 }, queries = {}, dbs = {}, closed = 0 }
      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "Hints: delete",
        "thread:abc  today [1/1] subject",
        "thread:def  today [1/1] other",
        "thread:ghi  today [1/1] keep",
      })
      vim.bo.filetype = "notmuch-threads"
      vim.cmd("runtime ftplugin/notmuch-threads.lua")
      vim.bo.modifiable = false

      with_mock_cnotmuch(state, function()
        silence_print(function()
          vim.cmd("2,3DelThread")
        end)
      end)

      H.same({ "del" }, t1.added)
      H.same({ "del" }, t2.added)
      H.same({ "inbox" }, t1.removed)
      H.same({ "inbox" }, t2.removed)
      H.same(
        { "Hints: delete", "thread:ghi  today [1/1] keep" },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
      H.eq(false, vim.bo.modifiable)
      H.eq(2, state.closed)

      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "delete.purge_del searches deleted threads and No confirmation runs no shell commands",
    run = function()
      local nm = require("notmuch")
      local refresh = require("notmuch.refresh")
      local delete = require("notmuch.delete")
      local old_search = nm.search_terms
      local old_refresh = refresh.refresh_search_buffer
      local old_call_function = vim.api.nvim_call_function
      local old_command = vim.api.nvim_command
      local searched, refreshed = nil, false
      local commands = {}
      nm.search_terms = function(query)
        searched = query
      end
      refresh.refresh_search_buffer = function()
        refreshed = true
      end
      vim.api.nvim_call_function = function(name, args)
        H.eq("confirm", name)
        H.contains(args[1], "Purge deleted emails?")
        return 2
      end
      vim.api.nvim_command = function(cmd)
        commands[#commands + 1] = cmd
      end

      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      delete.purge_del()
      local cb = map_callback("DD")
      H.ok(cb, "expected temporary DD purge keymap")
      cb()

      H.eq("tag:del and tag:/./", searched)
      H.same({}, commands)
      H.eq(false, refreshed)
      H.eq(nil, map_callback("DD"))

      nm.search_terms = old_search
      refresh.refresh_search_buffer = old_refresh
      vim.api.nvim_call_function = old_call_function
      vim.api.nvim_command = old_command
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "delete.purge_del Yes confirmation runs delete pipeline, reindexes, refreshes, and replaces keymap safely",
    run = function()
      local nm = require("notmuch")
      local refresh = require("notmuch.refresh")
      local delete = require("notmuch.delete")
      local old_search = nm.search_terms
      local old_refresh = refresh.refresh_search_buffer
      local old_call_function = vim.api.nvim_call_function
      local old_command = vim.api.nvim_command
      local searches, refreshed = {}, false
      local commands = {}
      nm.search_terms = function(query)
        searches[#searches + 1] = query
      end
      refresh.refresh_search_buffer = function()
        refreshed = true
      end
      vim.api.nvim_call_function = function()
        return 1
      end
      vim.api.nvim_command = function(cmd)
        commands[#commands + 1] = cmd
      end

      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      delete.purge_del()
      local first_cb = map_callback("DD")
      H.ok(first_cb, "expected DD keymap")
      delete.purge_del()
      local second_cb = map_callback("DD")
      H.ok(second_cb, "expected DD keymap after reset")
      H.ok(first_cb ~= second_cb, "expected purge_del to override temporary DD keymap")
      second_cb()

      H.same({ "tag:del and tag:/./", "tag:del and tag:/./" }, searches)
      H.same({
        "silent ! notmuch search --output=files --format=text0 tag:del and tag:/./ | xargs -0 rm",
        "silent ! notmuch new",
      }, commands)
      H.eq(true, refreshed)
      H.eq(nil, map_callback("DD"))

      nm.search_terms = old_search
      refresh.refresh_search_buffer = old_refresh
      vim.api.nvim_call_function = old_call_function
      vim.api.nvim_command = old_command
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
}
