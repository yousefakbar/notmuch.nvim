vim.opt.rtp:prepend(vim.fn.getcwd())

vim.pack.add({
  {
    src = "https://github.com/catppuccin/nvim",
    name = "catppuccin",
  },
})

require("catppuccin").setup({
  flavour = "mocha",
})
vim.cmd.colorscheme("catppuccin")

require("notmuch").setup({
  notmuch_db_path = vim.fn.getcwd() .. "/tests/tmp/mail",
  maildir_sync_cmd = "true",
  render_html_body = false,
})
