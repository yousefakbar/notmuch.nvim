local C = {}

-- Define default configuration of `notmuch.nvim`
--
-- This function defines the default configuration options of the plugin
-- including keymaps. The defaults can be overridden with options `opts` passed
-- by the user in the `setup()` function.
C.defaults = function()
  local name = vim.fn.system('notmuch config get user.name'):gsub('\n', '') or ''
  local email = vim.fn.system('notmuch config get user.primary_email'):gsub('\n', '') or ''
  local defaults = {
    notmuch_db_path = vim.fn.system('notmuch config get database.path'):gsub('\n', ''),
    from = name .. ' <' .. email .. '>',
    maildir_sync_cmd = 'mbsync -a',
    open_cmd = 'xdg-open',
    logfile = nil,
    sent_folder = nil,
    keymaps = { -- This should capture all notmuch.nvim related keymappings
      sendmail = '<C-g><C-g>',
    },
  }
  return defaults
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
  C.options = vim.tbl_deep_extend('force', C.defaults(), options)
end

return C
