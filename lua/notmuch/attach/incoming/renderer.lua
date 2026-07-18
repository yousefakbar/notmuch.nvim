local R = {}

local v = vim.api

-- -----------------------------------------------------------------------------
-- PRIVATE HELPERS
-- -----------------------------------------------------------------------------

local function normalize_window_config(config)
  config = config or {}

  return {
    type = config.type or 'float',
    width = config.width or 0.8,
    height = config.height or 0.8,
    border = config.border or 'rounded',
  }
end

local function resolve_dimension(value, total)
  if type(value) == 'number' and value > 0 and value <= 1 then
    return math.max(1, math.floor(total * value))
  end

  if type(value) == 'number' and value > 1 then
    return math.floor(value)
  end

  return math.max(1, math.floor(total * 0.8))
end

local function result_lines(result)
  local content = result and result.content or ''
  return vim.split(content, '\n', { plain = true })
end

local function default_title(result, attachment)
  if result and result.title and result.title ~= '' then
    return result.title
  end

  local filename = attachment and attachment.part and attachment.part.filename
  if filename and filename ~= '' then
    return filename
  end

  return 'Attachment preview'
end

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

---Render a normalized incoming attachment view result in a Neovim window.
---@param result NotmuchIncomingViewResult View result produced by viewer.view().
---@param attachment NotmuchIncomingAttachment|nil Incoming attachment object.
---@param opts table|nil View/render options. Uses `opts.window` when present.
---@return table rendered Rendered preview handles: `{ buf = integer, win = integer }`.
function R.render(result, attachment, opts)
  opts = opts or {}

  if type(result) ~= 'table' then
    error('notmuch.attach.incoming.renderer.render: result must be a table')
  end

  local window = normalize_window_config(opts.window)
  local buf = v.nvim_create_buf(false, true)
  v.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })

  local lines = result_lines(result)
  v.nvim_buf_set_lines(buf, 0, -1, false, lines)

  if result.filetype and result.filetype ~= '' then
    v.nvim_set_option_value('filetype', result.filetype, { buf = buf })
  end

  local width = resolve_dimension(window.width, vim.o.columns)
  local height = resolve_dimension(window.height, vim.o.lines)
  width = math.min(width, math.max(1, vim.o.columns))
  height = math.min(height, math.max(1, vim.o.lines - 1))

  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local win_opts = {
    border = window.border,
    relative = 'editor',
    style = 'minimal',
    height = height,
    width = width,
    row = row,
    col = col,
    title = default_title(result, attachment),
    title_pos = 'center',
  }

  local win = v.nvim_open_win(buf, true, win_opts)

  v.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.keymap.set('n', 'q', function()
    if v.nvim_win_is_valid(win) then
      v.nvim_win_close(win, false)
    end
  end, { buffer = buf, silent = true })

  return { buf = buf, win = win }
end

return R
