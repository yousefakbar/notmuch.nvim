local R = {}

---@alias NotmuchIncomingRuleMatcher
---| '"*"'
---| table
---| fun(attachment: NotmuchIncomingAttachment): boolean

---@alias NotmuchIncomingCommand
---| table
---| fun(attachment: NotmuchIncomingAttachment): table

---@class NotmuchIncomingRule
---@field name string Rule name used for replacement/disable patches.
---@field match NotmuchIncomingRuleMatcher Rule matcher.
---@field command? NotmuchIncomingCommand Open command definition.
---@field commands? NotmuchIncomingCommand[] View command fallback definitions.
---@field handler? fun(attachment: NotmuchIncomingAttachment): any,string|nil Custom rule handler returning a result or nil plus error.
---@field filetype? string Filetype for rendered view buffers.
---@field fallback? string|fun(attachment: NotmuchIncomingAttachment): string User-facing fallback message.
---@field detach? boolean Whether open commands should be detached processes.

---@class NotmuchIncomingRulePatches
---@field prepend? NotmuchIncomingRule[] Rules inserted before default rules.
---@field append? NotmuchIncomingRule[] Rules inserted after default rules.
---@field replace? table<string, NotmuchIncomingRule> Map of default rule name to replacement rule.
---@field disable? string[] Names of default rules to disable.

-- -----------------------------------------------------------------------------
-- PRIVATE HELPERS
-- -----------------------------------------------------------------------------

local function field_value(att, key)
  if key == "content_type" then
    return att.part and att.part.content_type
  elseif key == "ext" then
    return att.part and att.part.ext
  elseif key == "filename" then
    return att.part and att.part.filename
  elseif key == "disposition" then
    return att.part and att.part.disposition
  elseif key == "id" then
    return att.part and att.part.id
  elseif key == "size" then
    return att.part and att.part.size
  elseif key == "message_id" then
    return att.message and att.message.id
  end
end

local function value_matches(expected, actual, key)
  if expected == actual then
    return true
  end

  if key == "content_type" and type(expected) == "string" and expected:match("/%*$") then
    local prefix = expected:gsub("/%*$", "/")
    return type(actual) == "string" and vim.startswith(actual, prefix)
  end

  return false
end

local function table_matches(match, att)
  for key, expected in pairs(match) do
    local actual = field_value(att, key)
    if not value_matches(expected, actual, key) then
      return false
    end
  end

  return true
end

local function list_extend(dst, src)
  for _, item in ipairs(src or {}) do
    table.insert(dst, item)
  end
end

local function make_set(list)
  local set = {}
  for _, name in ipairs(list or {}) do
    set[name] = true
  end
  return set
end

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

---Return whether a rule matches an incoming attachment.
---
---Supported matcher forms:
--- - `match = "*"`                    - matches all attachments
--- - `match = function(att) ... end`  - uses custom Lua logic
--- - `match = { ... }`                - uses structured AND semantics
---
---@param rule NotmuchIncomingRule Rule table containing a `match` field.
---@param attachment NotmuchIncomingAttachment Incoming attachment object.
---@return boolean matches True when the rule matches the attachment.
function R.matches(rule, attachment)
  if type(rule) ~= "table" then
    return false
  end

  local matcher = rule.match

  if matcher == "*" then
    return true
  end

  if type(matcher) == "function" then
    local ok, matched = pcall(matcher, attachment)
    if not ok then
      vim.notify(
        string.format(
          "notmuch.nvim: attachment rule %q matcher failed: %s",
          tostring(rule.name or "<unnamed>"),
          tostring(matched)
        ),
        vim.log.levels.ERROR
      )
      return false
    end
    return matched and true or false
  end

  if type(matcher) == "table" then
    return table_matches(matcher, attachment)
  end

  return false
end

---Apply user rule patches to the default ruleset.
---
---Patch order:
--- 1. `prepend`
--- 2. default rules after `replace`/`disable`
--- 3. `append`
---
---Patch fields:
--- - `prepend`: rules inserted *before* the defaults.
--- - `append`: rules inserted *after* the defaults.
--- - `replace`: map of default rule name to the replacement rule.
--- - `disable`: list of default rule names to remove.
---
---`replace` and `disable` only apply to the default rules.
---
---@param default_rules NotmuchIncomingRule[] Default rules in their original order
---@param patches NotmuchIncomingRulePatches|nil Patch table with optional `prepend`, `append`, `replace`, and `disable` fields.
---@return NotmuchIncomingRule[] rules Effective ruleset after applying patches.
function R.apply_patches(default_rules, patches)
  default_rules = default_rules or {}
  patches = patches or {}

  -- Initialize the end result new ruleset
  local result = {}

  -- Add the `prepend` rule sets first
  list_extend(result, patches.prepend)

  -- Mark all rules in `patches.disable` to be removed from the new ruleset
  local disabled = make_set(patches.disable)
  local replace = patches.replace or {}

  for _, rule in ipairs(default_rules) do
    local name = rule.name

    if name and disabled[name] then
      -- If disabled rule, skip from being added to the new set
    elseif name and replace[name] then
      -- If marked for replacement and found in original set, replace with new
      table.insert(result, replace[name])
    else
      -- Otherwise just copy from the original to the new set
      table.insert(result, rule)
    end
  end

  -- Add the `append` rules at the end
  list_extend(result, patches.append)

  return result
end

---Expand a command definition into an argv array.
---
---Supported command forms:
--- - argv table, e.g. `{ "xdg-open", "$path" }`
--- - function, e.g. `function(att) return { "xdg-open", att.path } end`
---
---Only exact `$path` argv elements are substituted. Embedded occurrences such as
---`"file=$path"` are intentionally left unchanged.
---
---@param command NotmuchIncomingCommand Command argv table or function returning argv.
---@param attachment NotmuchIncomingAttachment Incoming attachment object.
---@return string[]|nil argv Expanded argv array, or nil on validation failure.
---@return string|nil err Error message when expansion fails.
function R.expand_command(command, attachment)
  local argv

  if type(command) == "function" then
    argv = command(attachment)
  elseif type(command) == "table" then
    argv = {}
    for _, arg in ipairs(command) do
      if arg == "$path" then
        if not attachment or not attachment.path then
          return nil, "cannot expand $path: attachment.path is nil"
        end
        table.insert(argv, attachment.path)
      else
        table.insert(argv, arg)
      end
    end
  else
    return nil, "command must be a table or function"
  end

  if type(argv) ~= "table" or #argv == 0 then
    return nil, "expanded command is empty"
  end

  return argv, nil
end

---Return the first rule that matches an incoming attachment.
---
---Rules are checked in order using `R.matches()`.
---
---@param ruleset NotmuchIncomingRule[] Ordered list of rules.
---@param attachment NotmuchIncomingAttachment Incoming attachment object.
---@return NotmuchIncomingRule|nil rule First matching rule, or nil if none match.
---@return integer|nil index Index of the matching rule, or nil if none match.
function R.first_match(ruleset, attachment)
  for index, rule in ipairs(ruleset or {}) do
    if R.matches(rule, attachment) then
      return rule, index
    end
  end

  return nil, nil
end

return R
