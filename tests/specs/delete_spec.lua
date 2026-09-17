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

local function map_callback(lhs, buf)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf or 0, "n")) do
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

local function with_purge_mocks(run)
  local nm = require("notmuch")
  local refresh = require("notmuch.refresh")
  local old_search = nm.search_terms
  local old_refresh = refresh.refresh_search_buffer
  local old_system = vim.system
  local old_unlink = vim.uv.fs_unlink
  local old_confirm = vim.fn.confirm
  local old_notify = vim.notify
  local state = {
    confirm = 2,
    prompts = {},
    searches = {},
    systems = {},
    unlinks = {},
    notes = {},
    refreshed = 0,
  }

  nm.search_terms = function(query)
    state.searches[#state.searches + 1] = query
  end
  refresh.refresh_search_buffer = function()
    state.refreshed = state.refreshed + 1
  end
  vim.system = function(argv, opts, callback)
    state.systems[#state.systems + 1] = {
      argv = vim.deepcopy(argv),
      opts = opts,
      callback = callback,
    }
    return {}
  end
  vim.uv.fs_unlink = function(path, callback)
    state.unlinks[#state.unlinks + 1] = {
      path = path,
      callback = callback,
    }
  end
  vim.fn.confirm = function(message, choices, default)
    state.prompts[#state.prompts + 1] = {
      message = message,
      choices = choices,
      default = default,
    }
    return state.confirm
  end
  vim.notify = function(message, level)
    state.notes[#state.notes + 1] = { message = message, level = level }
  end

  state.complete_system = function(index, result)
    state.systems[index].callback(result)
    vim.wait(20)
  end
  state.complete_unlink = function(index, err)
    state.unlinks[index].callback(err)
    vim.wait(20)
  end

  local ok, err = pcall(run, state)

  nm.search_terms = old_search
  refresh.refresh_search_buffer = old_refresh
  vim.system = old_system
  vim.uv.fs_unlink = old_unlink
  vim.fn.confirm = old_confirm
  vim.notify = old_notify

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
    name = "delete.purge_del uses tag:del, disarms DD, and cancellation deletes nothing",
    run = function()
      with_purge_mocks(function(state)
        local delete = require("notmuch.delete")
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, buf)

        delete.purge_del()
        local callback = map_callback("DD", buf)
        H.ok(callback, "expected temporary DD purge keymap")
        callback()

        H.same({ "tag:del" }, state.searches)
        H.eq(nil, map_callback("DD", buf))
        H.same(
          { "notmuch", "search", "--output=files", "--format=text0", "tag:del" },
          state.systems[1].argv
        )

        delete.purge_del()
        H.same({ "tag:del" }, state.searches)
        H.contains(state.notes[#state.notes].message, "already in progress")
        H.eq(vim.log.levels.WARN, state.notes[#state.notes].level)

        state.complete_system(1, {
          code = 0,
          stdout = "/mail/one\0/mail/two\0",
          stderr = "",
        })

        H.eq(1, #state.prompts)
        H.contains(state.prompts[1].message, "2 mail files")
        H.eq(2, state.prompts[1].default)
        H.eq(0, #state.unlinks)
        H.eq(1, #state.systems)
        H.eq(0, state.refreshed)

        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end,
  },
  {
    name = "delete.purge_del deduplicates paths, unlinks asynchronously, reindexes, and refreshes",
    run = function()
      with_purge_mocks(function(state)
        local delete = require("notmuch.delete")
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, buf)
        state.confirm = 1

        delete.purge_del()
        map_callback("DD", buf)()
        state.complete_system(1, {
          code = 0,
          stdout = "/mail/one\0/mail/two\0/mail/one\0",
          stderr = "",
        })

        H.eq(2, #state.unlinks)
        H.eq("/mail/one", state.unlinks[1].path)
        H.eq("/mail/two", state.unlinks[2].path)
        H.eq(1, #state.systems)

        state.complete_unlink(1, nil)
        H.eq(1, #state.systems)
        state.complete_unlink(2, nil)
        H.eq(2, #state.systems)
        H.same({ "notmuch", "new" }, state.systems[2].argv)

        state.complete_system(2, { code = 0, stdout = "", stderr = "" })
        H.eq(1, state.refreshed)
        H.contains(state.notes[#state.notes].message, "purged 2 mail files")
        H.eq(vim.log.levels.INFO, state.notes[#state.notes].level)

        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end,
  },
  {
    name = "delete.purge_del stops safely when the notmuch file search fails",
    run = function()
      with_purge_mocks(function(state)
        local delete = require("notmuch.delete")
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, buf)

        delete.purge_del()
        map_callback("DD", buf)()
        state.complete_system(1, { code = 2, stdout = "", stderr = "bad query" })

        H.eq(0, #state.prompts)
        H.eq(0, #state.unlinks)
        H.eq(1, #state.systems)
        H.eq(0, state.refreshed)
        H.contains(state.notes[#state.notes].message, "bad query")
        H.eq(vim.log.levels.ERROR, state.notes[#state.notes].level)

        -- Failure must release the global guard so another purge can be armed.
        delete.purge_del()
        H.same({ "tag:del", "tag:del" }, state.searches)
        H.ok(map_callback("DD", buf))

        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end,
  },
  {
    name = "delete.purge_del tracks missing and failed files and reports reindex failure",
    run = function()
      with_purge_mocks(function(state)
        local delete = require("notmuch.delete")
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, buf)
        state.confirm = 1

        delete.purge_del()
        map_callback("DD", buf)()
        state.complete_system(1, {
          code = 0,
          stdout = "/mail/deleted\0/mail/missing\0/mail/denied\0",
          stderr = "",
        })

        state.complete_unlink(1, nil)
        state.complete_unlink(2, "ENOENT: no such file or directory")
        state.complete_unlink(3, "EACCES: permission denied")
        H.same({ "notmuch", "new" }, state.systems[2].argv)

        state.complete_system(2, { code = 1, stdout = "", stderr = "database locked" })
        H.eq(0, state.refreshed)
        H.contains(state.notes[#state.notes].message, "`notmuch new` failed")
        H.contains(state.notes[#state.notes].message, "database locked")
        H.eq(vim.log.levels.ERROR, state.notes[#state.notes].level)

        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end,
  },
  {
    name = "delete.purge_del never refreshes a different current buffer",
    run = function()
      with_purge_mocks(function(state)
        local delete = require("notmuch.delete")
        local origin = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, origin)
        state.confirm = 1

        delete.purge_del()
        map_callback("DD", origin)()
        state.complete_system(1, {
          code = 0,
          stdout = "/mail/one\0",
          stderr = "",
        })
        state.complete_unlink(1, nil)

        local current = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_win_set_buf(0, current)
        state.complete_system(2, { code = 0, stdout = "", stderr = "" })

        H.eq(current, vim.api.nvim_get_current_buf())
        H.eq(true, vim.api.nvim_buf_is_valid(current))
        H.eq(false, vim.api.nvim_buf_is_valid(origin))
        H.eq(0, state.refreshed)

        vim.api.nvim_buf_delete(current, { force = true })
      end)
    end,
  },
}
