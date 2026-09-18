local H = dofile("tests/helpers.lua")

local function record_text(records)
  local lines = {}
  for _, record in ipairs(records) do
    table.insert(lines, record.kind .. ": " .. tostring(record.message))
    for _, advice in ipairs(record.advice or {}) do
      table.insert(lines, "advice: " .. tostring(advice))
    end
  end
  return table.concat(lines, "\n")
end

local function with_health_environment(spec, run)
  local config = require("notmuch.config")
  local old = {
    config_options = config.options,
    executable = vim.fn.executable,
    exepath = vim.fn.exepath,
    fs_stat = vim.uv.fs_stat,
    system = vim.system,
    health_module = package.loaded["notmuch.health"],
    ffi_module = package.loaded.ffi,
    ffi_preload = package.preload.ffi,
    health = {},
  }
  local records = {}

  for _, name in ipairs({ "start", "ok", "info", "warn", "error" }) do
    old.health[name] = vim.health[name]
    vim.health[name] = function(message, advice)
      table.insert(records, {
        kind = name,
        message = message,
        advice = advice,
      })
    end
  end

  config.options = spec.options
  vim.fn.executable = function(name)
    return spec.executables[name] and 1 or 0
  end
  vim.fn.exepath = function(name)
    return spec.executables[name] or ""
  end
  vim.uv.fs_stat = function(path)
    local value = spec.paths[path]
    if value then
      return value
    end
    return nil, "ENOENT"
  end
  vim.system = function(command)
    local response = spec.commands[table.concat(command, "\0")]
    return {
      wait = function(_, timeout)
        H.ok(timeout > 0, "expected a bounded command timeout")
        if type(response) == "function" then
          return response(command)
        end
        return response or { code = 1, stdout = "", stderr = "unexpected command" }
      end,
    }
  end

  package.loaded["notmuch.health"] = nil
  package.loaded.ffi = nil
  if spec.ffi then
    package.preload.ffi = function()
      return spec.ffi
    end
  else
    package.preload.ffi = function()
      error("ffi unavailable")
    end
  end

  local ok, err = pcall(function()
    require("notmuch.health").check()
    run(records)
  end)

  config.options = old.config_options
  vim.fn.executable = old.executable
  vim.fn.exepath = old.exepath
  vim.uv.fs_stat = old.fs_stat
  vim.system = old.system
  package.loaded["notmuch.health"] = old.health_module
  package.loaded.ffi = old.ffi_module
  package.preload.ffi = old.ffi_preload
  for name, value in pairs(old.health) do
    vim.health[name] = value
  end

  if not ok then
    error(err, 0)
  end
end

local function fake_ffi(load)
  return {
    cdef = function() end,
    load = load or function()
      return {}
    end,
    new = function() end,
    string = function() end,
  }
end

return {
  {
    name = "health reports a usable environment and all discovered dependencies",
    run = function()
      with_health_environment({
        ffi = fake_ffi(),
        executables = {
          notmuch = "/usr/bin/notmuch",
          msmtp = "/usr/bin/msmtp",
          mbsync = "/usr/bin/mbsync",
          w3m = "/usr/bin/w3m",
        },
        options = {
          notmuch_db_path = "/mail",
          maildir_sync_cmd = "mbsync -a",
          render_html_body = true,
        },
        paths = {
          ["/mail"] = { type = "directory" },
          ["/mail/.notmuch"] = { type = "directory" },
        },
        commands = {
          ["/usr/bin/notmuch\0--version"] = {
            code = 0,
            stdout = "notmuch 0.40\n",
            stderr = "",
          },
          ["/usr/bin/notmuch\0config\0get\0database.path"] = {
            code = 0,
            stdout = "/mail\n",
            stderr = "",
          },
          ["/usr/bin/notmuch\0count\0--output=threads\0*"] = {
            code = 0,
            stdout = "24\n",
            stderr = "",
          },
          ["/usr/bin/notmuch\0config\0get\0user.name"] = {
            code = 0,
            stdout = "Test User\n",
            stderr = "",
          },
          ["/usr/bin/notmuch\0config\0get\0user.primary_email"] = {
            code = 0,
            stdout = "test@example.com\n",
            stderr = "",
          },
        },
      }, function(records)
        local report = record_text(records)
        H.contains(report, "Neovim environment")
        H.contains(report, "LuaJIT FFI is available")
        H.contains(report, "Notmuch version: 0.40")
        H.contains(report, "libnotmuch loaded successfully")
        H.contains(report, "Database directory exists: /mail")
        H.contains(report, "queried the database successfully (24 threads)")
        H.contains(report, "Test User <test@example.com>")
        H.contains(report, "`msmtp` found: /usr/bin/msmtp")
        H.contains(report, "`mbsync` found: /usr/bin/mbsync")
        H.contains(report, "`w3m` found: /usr/bin/w3m")
      end)
    end,
  },
  {
    name = "health reports library database identity and optional dependency failures",
    run = function()
      with_health_environment({
        ffi = fake_ffi(function()
          error("libnotmuch.so: cannot open shared object file")
        end),
        executables = {
          notmuch = "/usr/bin/notmuch",
        },
        options = {
          notmuch_db_path = "/missing",
          maildir_sync_cmd = "mbsync -a",
          render_html_body = true,
        },
        paths = {},
        commands = {
          ["/usr/bin/notmuch\0--version"] = {
            code = 0,
            stdout = "notmuch 0.40\n",
            stderr = "",
          },
          ["/usr/bin/notmuch\0config\0get\0database.path"] = {
            code = 0,
            stdout = "/cli-mail\n",
            stderr = "",
          },
          ["/usr/bin/notmuch\0count\0--output=threads\0*"] = {
            code = 1,
            stdout = "",
            stderr = "No database found",
          },
          ["/usr/bin/notmuch\0config\0get\0user.name"] = {
            code = 0,
            stdout = "",
            stderr = "",
          },
          ["/usr/bin/notmuch\0config\0get\0user.primary_email"] = {
            code = 0,
            stdout = "",
            stderr = "",
          },
        },
      }, function(records)
        local report = record_text(records)
        H.contains(report, "libnotmuch could not be loaded")
        H.contains(report, "configured database path does not exist")
        H.contains(report, "use different database paths")
        H.contains(report, "could not query the database")
        H.contains(report, "user identity is incomplete")
        H.contains(report, "`msmtp` was not found")
        H.contains(report, "`mbsync` was not found")
        H.contains(report, "HTML rendering is enabled, but `w3m` was not found")
      end)
    end,
  },
  {
    name = "health gates FFI and Notmuch checks when prerequisites are missing",
    run = function()
      with_health_environment({
        ffi = nil,
        executables = {},
        options = nil,
        paths = {},
        commands = {},
      }, function(records)
        local report = record_text(records)
        H.contains(report, "LuaJIT FFI is not available")
        H.contains(report, "`notmuch` executable was not found")
        H.contains(report, "libnotmuch loading check skipped")
        H.contains(report, "configuration and database checks were skipped")
      end)
    end,
  },
}
