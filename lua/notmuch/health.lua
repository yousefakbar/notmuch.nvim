-- notmuch.health -- Health checks for notmuch.nvim.
--
-- This module must remain safe to load when notmuch.nvim setup has not run or
-- has failed. In particular, do not require notmuch.cnotmuch here: that module
-- loads libnotmuch and reads configured runtime state at module load time.

local M = {}

local STR_MINIMUM_SUPPORTED_NVIM = "0.10.0"
local MINIMUM_SUPPORTED_NVIM = {
  major = 0,
  minor = 10,
  patch = 0,
}
local COMMAND_TIMEOUT_MS = 3000
local DATABASE_PROBE_TIMEOUT_MS = 5000

-- Support both modern and older Neovim health-reporting function names so an
-- unsupported Neovim release can still explain why it is unsupported.
local health = {
  start = vim.health.start or vim.health.report_start,
  ok = vim.health.ok or vim.health.report_ok,
  info = vim.health.info or vim.health.report_info,
  warn = vim.health.warn or vim.health.report_warn,
  error = vim.health.error or vim.health.report_error,
}

---@class NotmuchHealthExecutable
---@field path string
---@field version? string
---@field major? integer
---@field minor? integer
---@field patch? integer

---@param version table
---@return string version_string
local function format_nvim_version(version)
  local formatted = string.format("%d.%d.%d", version.major, version.minor, version.patch)

  if version.prerelease then
    formatted = formatted .. "-dev"
  end

  return formatted
end

---@param actual table
---@param required table
---@return boolean
local function version_at_least(actual, required)
  if actual.major ~= required.major then
    return actual.major > required.major
  end

  if actual.minor ~= required.minor then
    return actual.minor > required.minor
  end

  return actual.patch >= required.patch
end

---@return boolean supported
local function check_neovim()
  local version = vim.version()
  local version_text = format_nvim_version(version)
  local supported = version_at_least(version, MINIMUM_SUPPORTED_NVIM)

  if supported then
    health.ok(
      ("Neovim %s meets the minimum requirement of %s"):format(
        version_text,
        STR_MINIMUM_SUPPORTED_NVIM
      )
    )
  else
    health.error(("Neovim %s is unsupported"):format(version_text), {
      "Upgrade to Neovim " .. STR_MINIMUM_SUPPORTED_NVIM .. " or newer.",
    })
  end

  local missing_apis = {}

  if type(vim.system) ~= "function" then
    table.insert(missing_apis, "vim.system")
  end

  if type(vim.uv) ~= "table" then
    table.insert(missing_apis, "vim.uv")
  end

  if #missing_apis > 0 then
    health.error("Required Neovim APIs are unavailable: " .. table.concat(missing_apis, ", "), {
      "Use an official or otherwise complete Neovim 0.10+ build.",
    })
    return false
  end

  health.ok("Required Neovim APIs are available")
  return supported
end

---@return table|nil ffi
local function check_ffi()
  local ok, ffi_or_error = pcall(require, "ffi")

  if not ok then
    health.error("LuaJIT FFI is not available", {
      "notmuch.nvim uses FFI to access libnotmuch.",
      "Use a Neovim build that includes LuaJIT.",
      "Error: " .. tostring(ffi_or_error),
    })
    return nil
  end

  local ffi = ffi_or_error
  local required_functions = {
    "cdef",
    "load",
    "new",
    "string",
  }
  local missing_functions = {}

  for _, name in ipairs(required_functions) do
    if type(ffi[name]) ~= "function" then
      table.insert(missing_functions, "ffi." .. name)
    end
  end

  if #missing_functions > 0 then
    health.error("LuaJIT FFI is incomplete", {
      "Missing interfaces: " .. table.concat(missing_functions, ", "),
      "Use a standard Neovim build that includes LuaJIT.",
    })
    return nil
  end

  health.ok("LuaJIT FFI is available")

  if jit and jit.version then
    health.info("LuaJIT version: " .. jit.version)
  end

  return ffi
end

---@param version string
---@return integer? major
---@return integer? minor
---@return integer? patch
local function parse_version(version)
  local major, minor, patch = version:match("^(%d+)%.(%d+)%.?(%d*)")

  if not major or not minor then
    return nil, nil, nil
  end

  return tonumber(major), tonumber(minor), tonumber(patch) or 0
end

---@param executable NotmuchHealthExecutable
---@param args string[]
---@param timeout_ms? integer
---@return vim.SystemCompleted? result
---@return string? error_message
local function run_executable(executable, args, timeout_ms)
  local command = { executable.path }
  vim.list_extend(command, args)

  local started, result_or_error = pcall(function()
    return vim.system(command, { text = true }):wait(timeout_ms or COMMAND_TIMEOUT_MS)
  end)

  if not started then
    return nil, tostring(result_or_error)
  end

  return result_or_error, nil
end

---@return NotmuchHealthExecutable|nil executable
local function check_notmuch_executable()
  if vim.fn.executable("notmuch") ~= 1 then
    health.error("`notmuch` executable was not found in $PATH", {
      "Install Notmuch using your system package manager.",
      "Ensure `notmuch --version` works in the environment used to start Neovim.",
    })
    return nil
  end

  local path = vim.fn.exepath("notmuch")

  if path == "" then
    path = "notmuch"
    health.warn("`notmuch` is executable, but its absolute path could not be resolved", {
      "The health check will invoke it using $PATH.",
    })
  else
    health.ok(("`notmuch` executable found: %s"):format(path))
  end

  if type(vim.system) ~= "function" then
    health.warn("Notmuch version check was skipped because vim.system is unavailable")
    return { path = path }
  end

  local executable = { path = path }
  local result, run_error = run_executable(executable, { "--version" })

  if not result then
    health.error("`notmuch --version` could not be executed", {
      "Path: " .. path,
      "Error: " .. tostring(run_error),
    })
    return executable
  end

  if result.code ~= 0 then
    local advice = {
      "Path: " .. path,
      "Exit code: " .. tostring(result.code),
    }

    local stderr = vim.trim(result.stderr or "")
    if stderr ~= "" then
      table.insert(advice, "Error: " .. stderr)
    end

    if result.code == 124 then
      table.insert(
        advice,
        ("The command may have exceeded the %d ms timeout."):format(COMMAND_TIMEOUT_MS)
      )
    end

    health.error("`notmuch --version` did not complete successfully", advice)
    return executable
  end

  local stdout = vim.trim(result.stdout or "")
  local first_line = stdout:match("([^\r\n]+)") or stdout

  if first_line == "" then
    health.warn("`notmuch --version` succeeded but returned no output", {
      "Path: " .. path,
    })
    return executable
  end

  -- Typical output is "notmuch 0.40" or "notmuch 0.38.3".
  local version = first_line:match("[Nn]otmuch%s+([%d][%w%.+%-]*)")

  if not version then
    health.warn("`notmuch` executed successfully, but its version could not be parsed", {
      "Path: " .. path,
      "Reported output: " .. first_line,
    })
    return executable
  end

  executable.version = version
  executable.major, executable.minor, executable.patch = parse_version(version)
  health.ok(("Notmuch version: %s"):format(version))

  if executable.major == 0 and executable.minor and executable.minor < 32 then
    health.warn("This Notmuch version uses the deprecated database-open API", {
      "notmuch.nvim will use its compatibility fallback.",
      "Upgrade to Notmuch 0.32 or newer when possible.",
    })
  end

  return executable
end

---@param ffi table
---@return userdata|nil library
local function check_libnotmuch(ffi)
  local ok, library_or_error = pcall(ffi.load, "notmuch")

  if not ok then
    health.error("libnotmuch could not be loaded", {
      "Install the libnotmuch runtime library using your system package manager.",
      "Some distributions package the Notmuch executable and shared library separately.",
      "Error: " .. tostring(library_or_error),
    })
    return nil
  end

  health.ok("libnotmuch loaded successfully")
  return library_or_error
end

---@param notmuch NotmuchHealthExecutable
---@param key string
---@return string? value
---@return string? error_message
local function get_notmuch_config(notmuch, key)
  local result, run_error = run_executable(notmuch, { "config", "get", key })

  if not result then
    return nil, run_error
  end

  if result.code ~= 0 then
    local stderr = vim.trim(result.stderr or "")
    return nil, stderr ~= "" and stderr or ("exit code " .. tostring(result.code))
  end

  local value = vim.trim(result.stdout or "")
  if value == "" then
    return nil, nil
  end

  return value, nil
end

---@return table? options
local function configured_options()
  local ok, config = pcall(require, "notmuch.config")
  if not ok or type(config.options) ~= "table" then
    return nil
  end

  return config.options
end

---@param path string
---@return string
local function normalize_path(path)
  return vim.fs.normalize(vim.fn.expand(path))
end

---@param notmuch NotmuchHealthExecutable
local function check_notmuch_configuration(notmuch)
  local options = configured_options()
  local cli_db_path, cli_path_error = get_notmuch_config(notmuch, "database.path")
  local configured_db_path = options and options.notmuch_db_path or nil
  local db_path = configured_db_path or cli_db_path

  if not db_path then
    local advice = {
      "Run `notmuch setup` or configure `notmuch_db_path` in notmuch.nvim.",
    }
    if cli_path_error then
      table.insert(advice, "Notmuch reported: " .. cli_path_error)
    end
    health.error("No Notmuch database path could be determined", advice)
  else
    db_path = normalize_path(db_path)
    local source = configured_db_path and "notmuch.nvim setup" or "Notmuch configuration"
    health.info(("Database path (%s): %s"):format(source, db_path))

    local stat, stat_error = vim.uv.fs_stat(db_path)
    if not stat then
      health.error("The configured database path does not exist", {
        "Path: " .. db_path,
        "Correct `notmuch_db_path` or run `notmuch setup`.",
        stat_error and ("Error: " .. tostring(stat_error)) or nil,
      })
    elseif stat.type ~= "directory" then
      health.error("The configured database path is not a directory", {
        "Path: " .. db_path,
      })
    else
      health.ok("Database directory exists: " .. db_path)

      local metadata_path = vim.fs.joinpath(db_path, ".notmuch")
      local metadata_stat = vim.uv.fs_stat(metadata_path)
      if metadata_stat and metadata_stat.type == "directory" then
        health.ok("Notmuch database metadata found: " .. metadata_path)
      else
        health.warn("No `.notmuch` directory was found under the database path", {
          "Path: " .. metadata_path,
          "The operational query below is the authoritative database check.",
        })
      end
    end
  end

  if configured_db_path and cli_db_path then
    local configured_normalized = normalize_path(configured_db_path)
    local cli_normalized = normalize_path(cli_db_path)
    if configured_normalized ~= cli_normalized then
      health.warn("notmuch.nvim and the Notmuch CLI use different database paths", {
        "notmuch.nvim: " .. configured_normalized,
        "Notmuch CLI: " .. cli_normalized,
        "CLI-based search and show operations use the Notmuch CLI path.",
      })
    end
  end

  local query_result, query_error =
    run_executable(notmuch, { "count", "--output=threads", "*" }, DATABASE_PROBE_TIMEOUT_MS)

  if not query_result then
    health.error("The Notmuch database query could not be started", {
      "Error: " .. tostring(query_error),
    })
  elseif query_result.code ~= 0 then
    local advice = {
      "Run `notmuch count --output=threads '*'` outside Neovim and resolve the error.",
    }
    local stderr = vim.trim(query_result.stderr or "")
    if stderr ~= "" then
      table.insert(advice, "Notmuch reported: " .. stderr)
    end
    if query_result.code == 124 then
      table.insert(
        advice,
        ("The query may have exceeded the %d ms timeout."):format(DATABASE_PROBE_TIMEOUT_MS)
      )
    end
    health.error("The Notmuch CLI could not query the database", advice)
  else
    local count = vim.trim(query_result.stdout or "")
    health.ok(("Notmuch CLI queried the database successfully (%s threads)"):format(count))
  end

  local user_name, name_error = get_notmuch_config(notmuch, "user.name")
  local primary_email, email_error = get_notmuch_config(notmuch, "user.primary_email")

  if user_name and primary_email then
    health.ok(("Notmuch user identity is configured: %s <%s>"):format(user_name, primary_email))
  else
    local advice = {
      "Run `notmuch setup` and configure user.name and user.primary_email.",
      "Reading mail may still work, but composing mail will use fallback values.",
    }
    if name_error then
      table.insert(advice, "user.name: " .. name_error)
    end
    if email_error then
      table.insert(advice, "user.primary_email: " .. email_error)
    end
    health.warn("Notmuch user identity is incomplete", advice)
  end
end

---@param name string
---@return string? path
local function executable_path(name)
  if vim.fn.executable(name) ~= 1 then
    return nil
  end

  local path = vim.fn.exepath(name)
  return path ~= "" and path or name
end

---@param options? table
local function check_optional_dependencies(options)
  local msmtp = executable_path("msmtp")
  if msmtp then
    health.ok("`msmtp` found: " .. msmtp)
  else
    health.warn("`msmtp` was not found in $PATH", {
      "Reading, searching, and tagging mail will continue to work.",
      "Sending composed messages requires msmtp.",
    })
  end

  local sync_command = options and options.maildir_sync_cmd or "mbsync -a"
  health.info("Configured sync command: " .. tostring(sync_command))

  local sync_executable = type(sync_command) == "string" and sync_command:match("^%s*([^%s]+)")
    or nil
  local sync_basename = sync_executable and vim.fs.basename(vim.fn.expand(sync_executable)) or nil

  if sync_basename == "mbsync" then
    local mbsync = executable_path(sync_executable)
    if mbsync then
      health.ok("`mbsync` found: " .. mbsync)
    else
      health.warn("`mbsync` was not found in $PATH", {
        "Plugin-driven synchronization will not work with the configured command.",
        "Install isync/mbsync or configure `maildir_sync_cmd` with another command.",
      })
    end
  else
    health.info("The custom sync command was not executed by the health check")
  end

  local html_enabled = options and options.render_html_body == true
  local w3m = executable_path("w3m")

  if w3m then
    health.ok("`w3m` found: " .. w3m)
    if not html_enabled then
      health.info("Inline HTML rendering is disabled")
    end
  elseif html_enabled then
    health.warn("Inline HTML rendering is enabled, but `w3m` was not found", {
      "Install w3m or set `render_html_body = false`.",
      "Plain-text messages and attachment fallbacks will continue to work.",
    })
  else
    health.info("`w3m` is not installed, but inline HTML rendering is disabled")
  end
end

M.check = function()
  health.start("Neovim environment")
  local nvim_supported = check_neovim()
  local ffi = check_ffi()

  health.start("Required Notmuch dependencies")
  local notmuch = check_notmuch_executable()
  local libnotmuch

  if ffi then
    libnotmuch = check_libnotmuch(ffi)
  else
    health.warn("libnotmuch loading check skipped because FFI is unavailable")
  end

  if not nvim_supported then
    health.warn("Some additional checks may be unreliable on this Neovim version")
  end

  health.start("Notmuch configuration")
  if notmuch then
    check_notmuch_configuration(notmuch)
  else
    health.warn("Notmuch configuration and database checks were skipped")
  end

  if notmuch and ffi and not libnotmuch then
    health.warn("Database access through notmuch.nvim will fail until libnotmuch can be loaded")
  end

  health.start("Optional dependencies")
  check_optional_dependencies(configured_options())
end

return M
