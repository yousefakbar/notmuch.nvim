local H = dofile("tests/helpers.lua")

return {
  {
    name = "async JSON search uses argv, schedules completion, and returns a cancellable handle",
    run = function()
      local old = vim.system
      local callback, argv, delivered
      local process = { kill = function() end }
      vim.system = function(args, opts, cb)
        argv, callback = args, cb
        H.eq(true, opts.text)
        return process
      end
      local ok, err = pcall(function()
        H.eq(
          process,
          require("notmuch.async").run_notmuch_search('subject:"hello; world"', function(result)
            delivered = result
          end)
        )
        H.same({ "notmuch", "search", "--format=json", 'subject:"hello; world"' }, argv)
        callback({ code = 0, stdout = "[]" })
        H.eq(nil, delivered)
        vim.wait(20)
        H.eq("[]", delivered.stdout)
      end)
      vim.system = old
      if not ok then
        error(err)
      end
    end,
  },
  {
    name = "async JSON search reports spawn failure through callback",
    run = function()
      local old = vim.system
      vim.system = function()
        error("spawn failed")
      end
      local result
      require("notmuch.async").run_notmuch_search("*", function(r)
        result = r
      end)
      vim.system = old
      vim.wait(20)
      H.eq(-1, result.code)
      H.contains(result.stderr, "spawn failed")
    end,
  },
}
