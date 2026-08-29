local O = {}

local defaults = require("notmuch.attach.incoming.defaults")
local rules = require("notmuch.attach.incoming.rules")

-- -----------------------------------------------------------------------------
-- PRIVATE HELPERS
-- -----------------------------------------------------------------------------

local function try_handler(rule, attachment)
  if type(rule.handler) ~= "function" then
    return false, "rule handler is not a function"
  end

  local ok, result, err = pcall(rule.handler, attachment)
  if not ok then
    return false, result
  end

  if result then
    return true, nil
  end

  return false, err or "handler failed"
end

local function is_executable(cmd)
  if not cmd or cmd == "" then
    return false
  end

  return vim.fn.executable(cmd) == 1
end

local function try_command(rule, attachment)
  if not rule.command then
    return false, "rule has no command"
  end

  local argv, err = rules.expand_command(rule.command, attachment)
  if not argv then
    return false, err
  end

  if not is_executable(argv[1]) then
    return false, "executable not found: " .. tostring(argv[1])
  end

  local ok, system_err = pcall(vim.system, argv, { detach = rule.detach == true })
  if not ok then
    return false, system_err
  end

  return true, nil
end

local function fallback_message(rule, attachment, err)
  local fallback = rule and rule.fallback

  if type(fallback) == "function" then
    local ok, msg = pcall(fallback, attachment)
    if ok and msg and msg ~= "" then
      return msg
    end
  elseif type(fallback) == "string" and fallback ~= "" then
    return fallback
  end

  return err or "Could not open attachment"
end

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

---Open an incoming attachment externally using configured open rules.
---@param attachment NotmuchIncomingAttachment Incoming attachment object.
---@param opts table|nil Open options/config.
---@return boolean ok True when an opener was successfully launched/handled.
---@return string|nil err Error message when no opener succeeds.
function O.open(attachment, opts)
  opts = opts or {}

  if type(attachment) ~= "table" then
    local err = "attachment must be a table"
    vim.notify(err, vim.log.levels.ERROR)
    return false, err
  end

  local effective_rules = rules.apply_patches(defaults.open_rules(), opts.rules or {})
  local last_err
  local last_rule
  local matched = false

  for _, rule in ipairs(effective_rules) do
    if rules.matches(rule, attachment) then
      matched = true
      last_rule = rule

      if rule.handler then
        local ok, err = try_handler(rule, attachment)
        if ok then
          return true, nil
        end
        last_err = err
      end

      if rule.command then
        local ok, err = try_command(rule, attachment)
        if ok then
          return true, nil
        end
        last_err = err
      end
    end
  end

  local message
  if matched then
    message = fallback_message(last_rule, attachment, last_err)
  else
    message = "No open rule matched attachment"
  end

  vim.notify(message, vim.log.levels.ERROR)
  return false, message
end

return O
