local C = {}

-- Define default configuration of `notmuch.nvim`
--
-- This function defines the default configuration options of the plugin
-- including keymaps. The defaults can be overridden with options `opts` passed
-- by the user in the `setup()` function.
C.defaults = function()
  -- Helper to safely get notmuch config variables
  local function get_notmuch_config(key, fallback)
    local result = vim.fn.system("notmuch config get " .. key):gsub("\n", "")
    if
      vim.v.shell_error ~= 0
      or result == ""
      or result:match("^%s*$")
      or result:match("notmuch setup")
    then
      if result:match("command not found") or result:match("not found") then
        vim.notify("notmuch command not found. Please install notmuch.", vim.log.levels.ERROR)
      end
      return fallback
    end
    return result
  end

  local name = get_notmuch_config("user.name", nil)
  local email = get_notmuch_config("user.primary_email", nil)
  local db_path = get_notmuch_config("database.path", nil)

  -- Validate required configuration form notmuch and fail-fast
  if not db_path then
    vim.notify(
      "notmuch.nvim: database.path not configured.\n" .. "Please run: notmuch setup",
      vim.log.levels.ERROR
    )
    return nil
  end

  -- Validate user name and email from notmuch config
  if not name or not email then
    vim.notify(
      "notmuch.nvim: user.name or user.primary_email not configured.\n"
        .. "Please run: notmuch setup",
      vim.log.levels.WARN
    )
    name = name or "User"
    email = email or "user@localhost"
  end

  local defaults = {
    notmuch_db_path = db_path,
    from = name .. " <" .. email .. ">",
    maildir_sync_cmd = "mbsync -a",
    logfile = nil,
    send = {
      -- terminal: Real PTY terminal with stdin support for password input
      -- background: Run silently in background, notifications only
      send_mode = "terminal", -- "terminal" | "background"
    },
    sync = {
      sync_mode = "buffer", -- "background" | "buffer" | "terminal"
      --   background: Silent sync in background, notifications only
      --   buffer: Structured async output in dedicated buffer, no stdin (default)
      --   terminal: Real PTY terminal with stdin support for GPG/OAuth prompts
    },
    queries = {}, -- Saved/pinned search queries shown in dashboard above Tags (hidden when empty)
    suppress_deprecation_warning = false, -- Used for API deprecation warning suppression
    render_html_body = false, -- True means prioritize displaying rendered HTML
    thread_view_mode = "threaded", -- "threaded" | "newest-first" | "oldest-first" - Thread view display mode
    drafts = {
      folder = vim.fs.joinpath(vim.fn.stdpath("data"), "notmuch.nvim", "drafts"),
      delete_sent = false,
      show_sent_drafts = false,
      auto_open_attachment_window = false,
    },
    attach = {
      incoming = {
        cache_dir = vim.fs.joinpath(vim.fn.stdpath('cache'), 'notmuch.nvim', 'attachments'),
        open = {
          rules = {
            prepend = {},
            append = {},
            replace = {},
            disable = {},
          },
        },
        view = {
          rules = {
            prepend = {},
            append = {},
            replace = {},
            disable = {},
          },
          window = {
            type = 'float',
            width = 0.8,
            height = 0.8,
            border = 'rounded',
          },
        },
      },
    },
    keymaps = { -- This should capture all notmuch.nvim related keymappings
      sendmail = "<C-g><C-g>",
      attachment_window = "<C-g><C-a>",
    },
  }
  return defaults
end

local function normalize_attachments_config(options)
  local attachments = options.attachments
  if type(attachments) ~= 'table' then
    return
  end

  options.attach = options.attach or {}
  options.attach.incoming = options.attach.incoming or {}

  local incoming = options.attach.incoming

  if attachments.cache_dir then
    incoming.cache_dir = attachments.cache_dir
  end

  if attachments.open then
    incoming.open = incoming.open or {}
    incoming.open.rules = incoming.open.rules or {}
    incoming.open.rules.prepend = incoming.open.rules.prepend or {}

    if vim.islist(attachments.open) then
      vim.list_extend(incoming.open.rules.prepend, attachments.open)
    else
      vim.notify(
        'notmuch.nvim: attachments.open must be a list of incoming attachment open rules',
        vim.log.levels.WARN
      )
    end
  end

  if attachments.view then
    incoming.view = incoming.view or {}
    incoming.view.rules = incoming.view.rules or {}
    incoming.view.rules.prepend = incoming.view.rules.prepend or {}

    if vim.islist(attachments.view) then
      vim.list_extend(incoming.view.rules.prepend, attachments.view)
    else
      vim.notify(
        'notmuch.nvim: attachments.view must be a list of incoming attachment view rules',
        vim.log.levels.WARN
      )
    end
  end

  if attachments.window then
    incoming.view = incoming.view or {}
    incoming.view.window = vim.tbl_deep_extend(
      'force',
      incoming.view.window or {},
      attachments.window
    )
  end
end

-- Setup config for `notmuch.nvim`
--
-- This function sets up the configuration options which control the behavior of
-- the plugin. These options are mainly controlled by `defaults()` but can be
-- overridden by the user with the `opts` table passed via their package manager
-- which will pass it through the `init.setup()` function on startup.
--
---@param opts table: contains user override configuration options
--
---@usage: see `init.lua`'s `setup()` function for invocation
C.setup = function(opts)
  local options = opts or {}
  local defaults = C.defaults()

  if not defaults then
    vim.notify(
      "notmuch.nvim: Failed to load. Please configure notmuch first.",
      vim.log.levels.ERROR
    )
    return false
  end

  normalize_attachments_config(options)

  -- If `notmuch_db_path` is set by user, expand it in case of tildes, etc.
  if options.notmuch_db_path then
    options.notmuch_db_path = vim.fn.expand(options.notmuch_db_path)
  end

  C.options = vim.tbl_deep_extend("force", defaults, options)

  -- If `attach.incoming.cache_dir` is set by user, expand it
  if C.options.attach and C.options.attach.incoming and C.options.attach.incoming.cache_dir then
    C.options.attach.incoming.cache_dir = vim.fn.expand(C.options.attach.incoming.cache_dir)
  end

  -- Validate and normalise the queries list
  if C.options.queries and #C.options.queries > 0 then
    local valid = {}
    for _, q in ipairs(C.options.queries) do
      if
        type(q) == "table"
        and type(q.name) == "string"
        and q.name ~= ""
        and type(q.query) == "string"
        and q.query ~= ""
      then
        table.insert(valid, { name = q.name, query = q.query })
      else
        vim.notify(
          'notmuch.nvim: skipping invalid query entry — each entry must be { name = "...", query = "..." }',
          vim.log.levels.WARN
        )
      end
    end
    C.options.queries = valid
  end

  -- Expand path for drafts if overridden
  if C.options.drafts and C.options.drafts.folder then
    C.options.drafts.folder = vim.fn.expand(C.options.drafts.folder)
  end

  return true
end

return C
