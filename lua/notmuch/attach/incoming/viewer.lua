local V = {}

local defaults = require('notmuch.attach.incoming.defaults')
local rules = require('notmuch.attach.incoming.rules')

---@class NotmuchIncomingViewResult
---@field content string Text content to render.
---@field filetype? string Buffer filetype to use when rendering.
---@field title? string Display title.
---@field rule? string Name of the rule that produced the result.
---@field source? string Source command/handler/fallback name if known.

-- -----------------------------------------------------------------------------
-- PRIVATE HELPERS
-- -----------------------------------------------------------------------------

local function default_title(att)
  local filename = att.part and att.part.filename
  if filename and filename ~= '' then
    return filename
  end

  local part_id = att.part and att.part.id
  if part_id then
    return 'part ' .. tostring(part_id)
  end

  return 'attachment'
end

local function normalize_result(value, rule, attachment, source)
  if type(value) == 'table' then
    return {
      content = value.content or '',
      filetype = value.filetype or rule.filetype or 'text',
      title = value.title or default_title(attachment),
      rule = value.rule or rule.name,
      source = value.source or source,
    }, nil
  end

  if type(value) == 'string' then
    return {
      content = value,
      filetype = rule.filetype or 'text',
      title = default_title(attachment),
      rule = rule.name,
      source = source,
    }, nil
  end

  return nil, 'view result must be a table or string'
end

local function fallback_content(rule, attachment, err)
  local fallback = rule.fallback

  if type(fallback) == 'function' then
    local ok, value = pcall(fallback, attachment)
    if ok and value and value ~= '' then
      return value
    end
  elseif type(fallback) == 'string' and fallback ~= '' then
    return fallback
  end

  return err
end

local function fallback_result(rule, attachment, err)
  local content = fallback_content(rule, attachment, err)
  if not content or content == '' then
    return nil, err or 'viewer failed'
  end

  return {
    content = content,
    filetype = rule.filetype or 'text',
    title = default_title(attachment),
    rule = rule.name,
    source = 'fallback',
  }, nil
end

local function is_executable(cmd)
  return cmd and cmd ~= '' and vim.fn.executable(cmd) == 1
end

local function try_handler(rule, attachment)
  if type(rule.handler) ~= 'function' then
    return nil, 'rule handler is not a function'
  end

  local ok, result, err = pcall(rule.handler, attachment)
  if not ok then
    return nil, result
  end

  if result then
    return normalize_result(result, rule, attachment, 'handler')
  end

  return nil, err or 'handler failed'
end

local function try_command(command, rule, attachment)
  local argv, err = rules.expand_command(command, attachment)
  if not argv then
    return nil, err
  end

  if not is_executable(argv[1]) then
    return nil, 'executable not found: ' .. tostring(argv[1])
  end

  local ok, obj = pcall(function()
    return vim.system(argv, { text = true }):wait()
  end)
  if not ok then
    return nil, obj
  end

  if obj.code ~= 0 then
    return nil, obj.stderr or ('command failed: ' .. table.concat(argv, ' '))
  end

  return normalize_result(obj.stdout or '', rule, attachment, argv[1])
end

local function try_commands(rule, attachment)
  if type(rule.commands) ~= 'table' then
    return nil, 'rule has no commands'
  end

  local last_err
  for _, command in ipairs(rule.commands) do
    local result, err = try_command(command, rule, attachment)
    if result then
      return result, nil
    end
    last_err = err
  end

  return nil, last_err or 'all commands failed'
end

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

---View an incoming attachment by converting it to a normalized view result.
---@param attachment NotmuchIncomingAttachment Incoming attachment object.
---@param opts table|nil View options/config.
---@return NotmuchIncomingViewResult|nil result Normalized view result, or nil on failure.
---@return string|nil err Error message when no viewer succeeds.
function V.view(attachment, opts)
  opts = opts or {}

  if type(attachment) ~= 'table' then
    return nil, 'attachment must be a table'
  end

  local effective_rules = rules.apply_patches(defaults.view_rules(), opts.rules or {})
  local matched = false
  local last_err

  for _, rule in ipairs(effective_rules) do
    if rules.matches(rule, attachment) then
      matched = true

      if rule.handler then
        local result, err = try_handler(rule, attachment)
        if result then
          return result, nil
        end
        last_err = err
      end

      if rule.commands then
        local result, err = try_commands(rule, attachment)
        if result then
          return result, nil
        end
        last_err = err
      end

      local result, err = fallback_result(rule, attachment, last_err)
      if result then
        return result, nil
      end

      last_err = err
    end
  end

  if not matched then
    return nil, 'No view rule matched attachment'
  end

  return nil, last_err or 'No viewer succeeded'
end

return V
