local H = dofile("tests/helpers.lua")

local function read_file(path)
  local fd = assert(io.open(path, "rb"))
  local data = fd:read("*a")
  fd:close()
  return data
end

local function permission_mode(path)
  local stat = vim.uv.fs_stat(path)
  return stat and bit.band(stat.mode, 511) or nil
end

local function with_mocked_system(result, fn)
  local old_system = vim.system
  local calls = {}

  vim.system = function(cmd, opts)
    calls[#calls + 1] = { cmd = cmd, opts = opts }
    return {
      wait = function()
        if type(opts.stdout) == "function" and result.stdout ~= nil then
          opts.stdout(nil, result.stdout)
          opts.stdout(nil, nil)
        end
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
      H.eq(vim.fs.joinpath("/tmp/cache", vim.fn.sha256("abc/123"), "2-..-unsafe-name.pdf"), path)
    end,
  },
  {
    name = "attach.incoming.extractor.cache_path avoids message id collisions",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local part = {
        id = 2,
        filename = "invoice.pdf",
        content_type = "application/pdf",
      }
      local opts = { cache_dir = "/tmp/cache" }

      local slash_path = assert(extractor.cache_path("a/b@example.com", part, opts))
      local hyphen_path = assert(extractor.cache_path("a-b@example.com", part, opts))
      local repeated_path = assert(extractor.cache_path("a/b@example.com", part, opts))

      H.ok(slash_path ~= hyphen_path, "distinct message ids must not share a cache path")
      H.eq(slash_path, repeated_path, "cache paths must be deterministic")
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
      H.eq(vim.fs.joinpath("/tmp/cache", vim.fn.sha256("msg1"), "1-notmuch.txt"), path)

      path, err = extractor.cache_path("msg1", {
        id = 2,
        content_type = "application/octet-stream",
      }, { cache_dir = "/tmp/cache" })

      H.eq(nil, err)
      H.eq(vim.fs.joinpath("/tmp/cache", vim.fn.sha256("msg1"), "2-notmuch.bin"), path)
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

      path, err = extractor.cache_path(
        "msg1",
        { id = "../../outside" },
        { cache_dir = "/tmp/cache" }
      )
      H.eq(nil, path)
      H.contains(err, "part.id must be a positive integer")
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_path runs notmuch argv and streams stdout",
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
        H.eq(false, calls[1].opts.text)
        H.eq("function", type(calls[1].opts.stdout))
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

      with_mocked_system({ code = 1, stdout = "partial", stderr = "boom" }, function()
        local saved, err = extractor.extract_to_path("msg1", 4, out)

        H.eq(nil, saved)
        H.contains(err, "boom")
        H.eq(0, vim.fn.filereadable(out))
        H.same({}, vim.fn.glob(out .. ".tmp-*", false, true))
      end)
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_path preserves destination after failure",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local out = vim.fs.joinpath(dir, "out.txt")
      H.write_file(out, "existing attachment")

      with_mocked_system({ code = 1, stdout = "partial", stderr = "boom" }, function()
        local saved, err = extractor.extract_to_path("msg1", 4, out)

        H.eq(nil, saved)
        H.contains(err, "boom")
        H.eq("existing attachment", read_file(out))
        H.same({}, vim.fn.glob(out .. ".tmp-*", false, true))
      end)
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_path cleans up after write failures",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local out = vim.fs.joinpath(dir, "out.txt")
      local old_fs_write = vim.uv.fs_write

      vim.uv.fs_write = function()
        return nil, "disk full"
      end

      local ok, test_err = pcall(function()
        with_mocked_system({ code = 0, stdout = "attachment", stderr = "" }, function()
          local saved, err = extractor.extract_to_path("msg1", 4, out)

          H.eq(nil, saved)
          H.contains(err, "disk full")
          H.eq(0, vim.fn.filereadable(out))
          H.same({}, vim.fn.glob(out .. ".tmp-*", false, true))
        end)
      end)

      vim.uv.fs_write = old_fs_write
      if not ok then
        error(test_err, 0)
      end
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_path cleans up after close failures",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local out = vim.fs.joinpath(dir, "out.txt")
      local old_fs_close = vim.uv.fs_close

      vim.uv.fs_close = function(fd)
        old_fs_close(fd)
        return nil, "close failed"
      end

      local ok, test_err = pcall(function()
        with_mocked_system({ code = 0, stdout = "attachment", stderr = "" }, function()
          local saved, err = extractor.extract_to_path("msg1", 4, out)

          H.eq(nil, saved)
          H.contains(err, "close failed")
          H.eq(0, vim.fn.filereadable(out))
          H.same({}, vim.fn.glob(out .. ".tmp-*", false, true))
        end)
      end)

      vim.uv.fs_close = old_fs_close
      if not ok then
        error(test_err, 0)
      end
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
    name = "attach.incoming.extractor.extract_to_cache creates private directories and files",
    run = function()
      local extractor = require("notmuch.attach.incoming.extractor")
      local cache_dir = vim.fs.joinpath(H.tmpdir(), "nested", "cache")
      local part = { id = 2, filename = "doc.txt", content_type = "text/plain" }

      with_mocked_system({ code = 0, stdout = "cached", stderr = "" }, function()
        local path, err = extractor.extract_to_cache("msg1", part, { cache_dir = cache_dir })

        H.ok(path)
        H.eq(nil, err)
        H.eq("cached", read_file(path))
        if vim.fn.has("win32") == 0 then
          H.eq(448, permission_mode(vim.fn.fnamemodify(path, ":h")))
          H.eq(384, permission_mode(path))
        end
      end)
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_cache repairs existing cache directory permissions",
    run = function()
      if vim.fn.has("win32") == 1 then
        return
      end

      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local part = { id = 2, filename = "doc.txt", content_type = "text/plain" }
      local expected = assert(extractor.cache_path("msg1", part, { cache_dir = dir }))
      local cache_parent = vim.fn.fnamemodify(expected, ":h")
      vim.fn.mkdir(cache_parent, "p")
      assert(vim.uv.fs_chmod(cache_parent, 493)) -- 0755
      H.write_file(expected, "cached")

      local old_system = vim.system
      vim.system = function()
        error("vim.system should not be called for cached extraction")
      end

      local ok, err = pcall(function()
        local path, extract_err = extractor.extract_to_cache("msg1", part, { cache_dir = dir })
        H.eq(expected, path)
        H.eq(nil, extract_err)
        H.eq(448, permission_mode(cache_parent))
      end)

      vim.system = old_system
      if not ok then
        error(err, 0)
      end
    end,
  },
  {
    name = "attach.incoming.extractor.extract_to_cache reports permission hardening failures",
    run = function()
      if vim.fn.has("win32") == 1 then
        return
      end

      local extractor = require("notmuch.attach.incoming.extractor")
      local dir = H.tmpdir()
      local part = { id = 2, filename = "doc.txt", content_type = "text/plain" }
      local old_chmod = vim.uv.fs_chmod
      local old_system = vim.system
      local system_called = false

      vim.uv.fs_chmod = function()
        return nil, "permission denied"
      end
      vim.system = function()
        system_called = true
        error("vim.system should not run when cache permissions cannot be secured")
      end

      local ok, test_err = pcall(function()
        local path, err = extractor.extract_to_cache("msg1", part, { cache_dir = dir })
        H.eq(nil, path)
        H.contains(err, "permission denied")
        H.eq(false, system_called)
      end)

      vim.uv.fs_chmod = old_chmod
      vim.system = old_system
      if not ok then
        error(test_err, 0)
      end
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
      if vim.fn.has("win32") == 0 then
        assert(vim.uv.fs_chmod(dir, 493)) -- 0755
      end
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
        if vim.fn.has("win32") == 0 then
          H.eq(493, permission_mode(dir), "save_to_path must not chmod user directories")
        end
      end)
    end,
  },
}
