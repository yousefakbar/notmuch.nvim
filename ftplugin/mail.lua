if vim.startswith(vim.fs.basename(vim.api.nvim_buf_get_name(0)), "thread:") then
  local tag = require("notmuch.tag")
  local parts = require("notmuch.attach.parts")

  vim.opt_local.foldmethod = "marker"
  vim.opt_local.foldlevel = 0

  vim.api.nvim_buf_create_user_command(0, "TagAdd", function(arg)
    tag.msg_add_tag(arg.args)
  end, {
    complete = require("notmuch.completion").comp_tags,
    nargs = "+",
    force = true,
  })
  vim.api.nvim_buf_create_user_command(0, "TagRm", function(arg)
    tag.msg_rm_tag(arg.args)
  end, {
    complete = require("notmuch.completion").comp_tags,
    nargs = "+",
    force = true,
  })
  vim.api.nvim_buf_create_user_command(0, "TagToggle", function(arg)
    tag.msg_toggle_tag(arg.args)
  end, {
    complete = require("notmuch.completion").comp_tags,
    nargs = "+",
    force = true,
  })

  vim.keymap.set("n", "<Tab>", "zj", { buffer = true, silent = true })
  vim.keymap.set("n", "<S-Tab>", "zk", { buffer = true, silent = true })
  vim.keymap.set("n", "<Enter>", "za", { buffer = true, silent = true })
  vim.keymap.set("n", "a", parts.get_attachments_from_cursor_msg, { buffer = true })
  vim.keymap.set("n", "r", require("notmuch.refresh").refresh_thread_buffer, { buffer = true })
  vim.keymap.set("n", "C", require("notmuch.send").compose, { buffer = true })
  vim.keymap.set("n", "R", require("notmuch.send").reply, { buffer = true })
  vim.keymap.set("n", "q", "<Cmd>bwipeout<CR>", { buffer = true })
  vim.keymap.set("n", "+", ":TagAdd<Space>", { buffer = true })
  vim.keymap.set("n", "-", ":TagRm<Space>", { buffer = true })
  vim.keymap.set("n", "=", ":TagToggle<Space>", { buffer = true })
end
