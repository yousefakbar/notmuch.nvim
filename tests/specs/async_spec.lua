local H = dofile("tests/helpers.lua")

return {
  {
    name = "stream parser handles byte splits, nesting, escapes, and truncated input",
    run = function()
      local parser = require("notmuch.search.stream").new()
      local json = [[[{"thread":"abc","subject":"a } \" quote","query":["x",null]},]]
        .. [[{"thread":"def","tags":["one","two"]}]]
        .. "]"
      local objects = {}
      for i = 1, #json do
        parser:feed(json:sub(i, i))
        local batch, err = parser:drain(1, 3)
        H.eq(nil, err)
        vim.list_extend(objects, batch)
      end
      while parser:has_input() do
        local batch, err = parser:drain(1, 3)
        H.eq(nil, err)
        vim.list_extend(objects, batch)
      end
      H.eq(true, parser:finish())
      H.eq(2, #objects)
      H.eq('a } " quote', vim.json.decode(objects[1]).subject)
      H.eq(vim.NIL, vim.json.decode(objects[1]).query[2])

      local truncated = require("notmuch.search.stream").new()
      truncated:feed([[ [{"thread":"abc"}]])
      truncated:drain(10, 1000)
      local ok, err = truncated:finish()
      H.eq(nil, ok)
      H.contains(err, "Truncated")

      for _, invalid in ipairs({ '[{"thread":"abc"},false]', "[] trailing" }) do
        local malformed = require("notmuch.search.stream").new()
        malformed:feed(invalid)
        local _, parse_error = malformed:drain(10, 1000)
        H.ok(parse_error)
      end
    end,
  },
  {
    name = "streaming search handles spawn errors, malformed tails, and cancellation",
    run = function()
      local async = require("notmuch.async")
      local old = vim.system
      local ok, err = pcall(function()
        vim.system = function()
          error("stream spawn failed")
        end
        local spawn_result
        local failed = async.stream_notmuch_search("*", {
          on_complete = function(result)
            spawn_result = result
          end,
        })
        H.eq("function", type(failed.kill))
        H.wait_until(function()
          return spawn_result ~= nil
        end)
        H.eq(-1, spawn_result.code)
        H.contains(spawn_result.stderr, "stream spawn failed")

        local opts, on_exit
        local killed = false
        vim.system = function(_, system_opts, callback)
          opts, on_exit = system_opts, callback
          return {
            kill = function()
              killed = true
            end,
          }
        end
        local batches, result = {}, nil
        local request = async.stream_notmuch_search("*", {
          on_records = function(records)
            vim.list_extend(batches, records)
          end,
          on_complete = function(value)
            result = value
          end,
        })
        local valid = {
          thread = "abc",
          timestamp = 1,
          date_relative = "today",
          matched = 1,
          total = 1,
          authors = "A",
          subject = "one",
          tags = {},
        }
        opts.stdout(nil, "[" .. vim.json.encode(valid) .. ",")
        H.wait_until(function()
          return #batches == 1
        end)
        opts.stdout(nil, "false]")
        opts.stdout(nil, nil)
        on_exit({ code = 0, signal = 0 })
        H.wait_until(function()
          return result ~= nil
        end)
        H.eq(1, #batches)
        H.eq(-1, result.code)
        H.ok(result.parse_error)
        H.eq(true, killed)

        batches, result, killed = {}, nil, false
        request = async.stream_notmuch_search("*", {
          on_records = function(records)
            vim.list_extend(batches, records)
          end,
          on_complete = function(value)
            result = value
          end,
        })
        opts.stdout(nil, "[" .. vim.json.encode(valid) .. "]")
        opts.stdout(nil, nil)
        on_exit({ code = 0, signal = 0 })
        request:kill()
        vim.wait(20)
        H.eq(true, killed)
        H.eq(0, #batches)
        H.eq(nil, result)
      end)
      vim.system = old
      if not ok then
        error(err)
      end
    end,
  },
  {
    name = "streaming search decodes bounded batches without retaining complete stdout",
    run = function()
      local old = vim.system
      local argv, system_opts, on_exit
      local process = { kill = function() end }
      vim.system = function(args, opts, callback)
        argv, system_opts, on_exit = args, opts, callback
        return process
      end
      local batches, completed = {}, nil
      local ok, err = pcall(function()
        local request = require("notmuch.async").stream_notmuch_search("tag:inbox", {
          on_records = function(records)
            batches[#batches + 1] = records
          end,
          on_complete = function(result)
            completed = result
          end,
        }, { sort = "oldest-first", records_per_tick = 1 })
        H.ok(request)
        H.same({ "notmuch", "search", "--format=json", "--sort=oldest-first", "tag:inbox" }, argv)
        local records = {
          {
            thread = "abc",
            timestamp = 1,
            date_relative = "today",
            matched = 1,
            total = 1,
            authors = "A",
            subject = "one",
            tags = {},
          },
          {
            thread = "def",
            timestamp = 2,
            date_relative = "today",
            matched = 1,
            total = 1,
            authors = "B",
            subject = "two",
            tags = {},
          },
        }
        local json = vim.json.encode(records)
        system_opts.stdout(nil, json:sub(1, 13))
        system_opts.stdout(nil, json:sub(14))
        system_opts.stdout(nil, nil)
        on_exit({ code = 0, signal = 0 })
        H.wait_until(function()
          return completed ~= nil
        end)
        H.eq(2, #batches)
        H.eq(1, #batches[1])
        H.eq("abc", batches[1][1].thread)
        H.eq(0, completed.code)
      end)
      vim.system = old
      if not ok then
        error(err)
      end
    end,
  },
}
