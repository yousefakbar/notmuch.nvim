local H = dofile("tests/helpers.lua")

return {
  {
    name = "util.empty_attachment_window detects empty and non-empty buffers",
    run = function()
      local util = require("notmuch.util")
      local buf = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "   " })
      H.eq(true, util.empty_attachment_window(buf))

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "file.txt" })
      H.eq(false, util.empty_attachment_window(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "util.format_size formats boundary values",
    run = function()
      local util = require("notmuch.util")
      H.eq("—", util.format_size(nil))
      H.eq("—", util.format_size(0))
      H.eq("42B", util.format_size(42))
      H.eq("2K", util.format_size(2048))
      H.eq("1.5M", util.format_size(1536 * 1024))
      H.eq("2.0G", util.format_size(2 * 1024 * 1024 * 1024))
    end,
  },
  {
    name = "util file and split helpers work",
    run = function()
      local util = require("notmuch.util")
      local dir = H.tmpdir()
      local file = H.write_file(dir .. "/sample.txt", "hello")

      H.eq(true, util.file_exists(file))
      H.eq(false, util.file_exists(dir .. "/missing.txt"))
      H.same({ "one", "two", "three" }, util.split("one two  three", "%S+"))
      H.same({ "abc", "def", "g" }, util.split_length("abcdefg", 3))
    end,
  },
  {
    name = "util.validate_attachment_file accepts files and rejects invalid paths",
    run = function()
      local util = require("notmuch.util")
      local dir = H.tmpdir()
      local file = H.write_file(dir .. "/ok.txt", "hello")

      local valid, err = util.validate_attachment_file(file)
      H.eq(true, valid)
      H.eq(nil, err)

      valid, err = util.validate_attachment_file(dir)
      H.eq(false, valid)
      H.contains(err, "not a regular file")

      valid, err = util.validate_attachment_file(dir .. "/missing.txt")
      H.eq(false, valid)
      H.ok(err and #err > 0, "expected missing-file error")

      valid, err = util.validate_attachment_file("/dev/null")
      H.eq(false, valid)
      H.contains(err, "not a regular file")
    end,
  },
  {
    name = "util.find_cursor_msg_id finds nearest previous message id",
    run = function()
      local util = require("notmuch.util")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "Subject: one",
        "id:first {{{",
        "body",
        "id:second {{{",
        "more body",
      })
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      H.eq("second", util.find_cursor_msg_id())
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "util.find_cursor_msg_id returns nil and prints when no id is found",
    run = function()
      local util = require("notmuch.util")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Subject: none", "body" })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local old_print = print
      local msg
      print = function(text)
        msg = text
      end
      H.eq(nil, util.find_cursor_msg_id())
      H.contains(msg, "No ID found")
      print = old_print
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
}
