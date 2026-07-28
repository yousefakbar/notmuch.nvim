local H = dofile("tests/helpers.lua")

local function read_file(path)
  local fd = assert(io.open(path, "rb"))
  local data = fd:read("*a")
  fd:close()
  return data
end

local function with_mocked_system(result, fn)
  local old_system = vim.system
  local calls = {}

  vim.system = function(cmd, opts)
    calls[#calls + 1] = { cmd = cmd, opts = opts }
    return {
      wait = function()
        return result
      end,
    }
  end

  local ok, err = pcall(fn, calls)
  vim.system = old_system
  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "attach.incoming.extractor.cache_path builds deterministic sanitized paths",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local path, err = extractor.cache_path("id:abc/123", {
        id = 2,
        filename = "../unsafe/name.pdf",
        content_type = "application/pdf",
      }, { cache_dir = "/tmp/cache" })

      H.eq(nil, err)
      H.eq(vim.fs.joinpath("/tmp/cache", "abc-123", "2-..-unsafe-name.pdf"), path)
    end,
  },
  {
    name = "attach.incoming.extractor.cache_path uses fallback filenames from content type",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local path, err = extractor.cache_path("msg1", {
        id = 1,
        filename = "",
        content_type = "text/plain",
      }, { cache_dir = "/tmp/cache" })

      H.eq(nil, err)
      H.eq(vim.fs.joinpath("/tmp/cache", "msg1", "1-notmuch.txt"), path)

      path, err = extractor.cache_path("msg1", {
        id = 2,
        content_type = "application/octet-stream",
      }, { cache_dir = "/tmp/cache" })

      H.eq(nil, err)
      H.eq(vim.fs.joinpath("/tmp/cache", "msg1", "2-notmuch.bin"), path)
    end,
  },
  {
    name = "attach.incoming.extractor.cache_path reports validation errors",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local path, err

      path, err = extractor.cache_path("msg1", nil, { cache_dir = "/tmp/cache" })
      H.eq(nil, path)
      H.contains(err, "part must be a table")

      path, err = extractor.cache_path(nil, { id = 1 }, { cache_dir = "/tmp/cache" })
      H.eq(nil, path)
      H.contains(err, "message_id is required")

      path, err = extractor.cache_path("msg1", {}, { cache_dir = "/tmp/cache" })
      H.eq(nil, path)
      H.contains(err, "part.id is required")
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_path runs notmuch argv and writes stdout",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local out = vim.fs.joinpath(dir, "nested", "out.txt")

      with_mocked_system({ code = 0, stdout = "hello attachment", stderr = "" }, function(calls)
        local saved, err = extractor.extract_to_path("id:msg1", 3, out)

        H.eq(out, saved)
        H.eq(nil, err)
        H.eq(1, #calls)
        H.same({
          "notmuch",
          "show",
          "--exclude=false",
          "--part=3",
          "id:msg1",
        }, calls[1].cmd)
        H.same({ text = false }, calls[1].opts)
        H.eq("hello attachment", read_file(out))
      end)
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_path reports notmuch failures",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local out = vim.fs.joinpath(dir, "out.txt")

      with_mocked_system({ code = 1, stdout = "", stderr = "boom" }, function()
        local saved, err = extractor.extract_to_path("msg1", 4, out)

        H.eq(nil, saved)
        H.contains(err, "boom")
        H.eq(0, vim.fn.filereadable(out))
      end)
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_path validates required inputs",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local out = vim.fs.joinpath(dir, "out.txt")
      local saved, err

      saved, err = extractor.extract_to_path(nil, 1, out)
      H.eq(nil, saved)
      H.contains(err, "message_id is required")

      saved, err = extractor.extract_to_path("msg1", nil, out)
      H.eq(nil, saved)
      H.contains(err, "part_id is required")

      saved, err = extractor.extract_to_path("msg1", 1, "")
      H.eq(nil, saved)
      H.contains(err, "path is required")
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_cache reuses existing cached files",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local part = { id = 2, filename = "doc.txt", content_type = "text/plain" }
      local expected = assert(extractor.cache_path("msg1", part, { cache_dir = dir }))
      vim.fn.mkdir(vim.fn.fnamemodify(expected, ":h"), "p")
      H.write_file(expected, "cached")

      local old_system = vim.system
      local called = false
      vim.system = function()
        called = true
        error("vim.system should not be called for cached extraction")
      end

      local ok, err = pcall(function()
        local path, extract_err = extractor.extract_to_cache("msg1", part, { cache_dir = dir })
        H.eq(expected, path)
        H.eq(nil, extract_err)
        H.eq(false, called)
        H.eq("cached", read_file(expected))
      end)

      vim.system = old_system
      if not ok then
        error(err, 0)
      end
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_cache force re-extracts cached files",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local part = { id = 2, filename = "doc.txt", content_type = "text/plain" }
      local expected = assert(extractor.cache_path("msg1", part, { cache_dir = dir }))
      vim.fn.mkdir(vim.fn.fnamemodify(expected, ":h"), "p")
      H.write_file(expected, "old cached")

      with_mocked_system({ code = 0, stdout = "new cached", stderr = "" }, function(calls)
        local path, err =
          extractor.extract_to_cache("msg1", part, { cache_dir = dir, force = true })

        H.eq(expected, path)
        H.eq(nil, err)
        H.eq(1, #calls)
        H.eq("new cached", read_file(expected))
      end)
    end,
  },
  {
    name = "attach.incoming.extractor.save_to_path validates part and extracts to requested path",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local out = vim.fs.joinpath(dir, "saved.txt")
      local saved, err = extractor.save_to_path("msg1", nil, out)

      H.eq(nil, saved)
      H.contains(err, "part must be a table")

      with_mocked_system({ code = 0, stdout = "saved body", stderr = "" }, function(calls)
        saved, err = extractor.save_to_path("id:msg1", { id = 5 }, out)

        H.eq(out, saved)
        H.eq(nil, err)
        H.same({
          "notmuch",
          "show",
          "--exclude=false",
          "--part=5",
          "id:msg1",
        }, calls[1].cmd)
        H.eq("saved body", read_file(out))
      end)
    end,
  },
}
