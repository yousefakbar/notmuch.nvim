-- Headless test init for notmuch.nvim.
-- Usage:
--   tests/scripts/setup-notmuch-db.sh
--   nvim --headless -u tests/test-init.lua -l tests/run.lua

local root = vim.fn.getcwd()
local test_home = root .. "/tests/tmp/home"
local test_mail = root .. "/tests/tmp/mail"

vim.env.HOME = test_home
vim.env.NOTMUCH_CONFIG = test_home .. "/.notmuch-config"

vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

if vim.fn.isdirectory(test_mail .. "/.notmuch") == 0 then
  error("Missing test notmuch database. Run tests/scripts/setup-notmuch-db.sh first.")
end

local ok, notmuch = pcall(require, "notmuch")
if not ok then
  error("failed to require notmuch: " .. tostring(notmuch))
end

notmuch.setup({
  notmuch_db_path = test_mail,
  maildir_sync_cmd = "true",
  render_html_body = false,
  suppress_deprecation_warning = true,
})

-- Avoid blocking headless runs if a spec accidentally reaches an interactive picker.
-- Specs that assert picker behavior should replace this stub locally.
vim.ui.select = function(_, _, on_choice)
  if on_choice then
    on_choice(nil)
  end
end
