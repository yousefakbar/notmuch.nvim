local nm = {}
local v = vim.api
local f = require'notmuch.float'
local m = require'notmuch.msg'
local u = require'notmuch.util'

nm.show_all_tags = function()
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "Tags")
  v.nvim_win_set_buf(0, buf)
  v.nvim_command("silent 0read! notmuch search --output=tags '*'")
  v.nvim_win_set_cursor(0, { 1, 0})
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-hello"
  vim.bo.modifiable = false
  print("Welcome to Notmuch.nvim! Choose a tag to search it.")
end

nm.show_tag = function(tag)
  if tag == '' then return nil end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "tag:" .. tag)
  v.nvim_win_set_buf(0, buf)
  v.nvim_command("silent 0read! notmuch search tag:" .. tag)
  v.nvim_win_set_cursor(0, { 1, 0})
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-threads"
  vim.bo.modifiable = false
end

nm.search_terms = function(search)
  if search == '' then return nil end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, search)
  v.nvim_win_set_buf(0, buf)
  v.nvim_command("silent 0read! notmuch search " .. search)
  v.nvim_win_set_cursor(0, { 1, 0})
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-threads"
  vim.bo.modifiable = false
end

-- TODO: implement folding for each message in a thread
-- User presses <CR> on a thread, pass the line to this function
nm.show_thread = function()
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, "[0-9a-z]+", 7)
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "thread:" .. threadid)
  v.nvim_win_set_buf(0, buf)
  v.nvim_command("0read! notmuch show thread:" .. threadid .. " | sed 's///g'")
  v.nvim_command('silent %s/message}//')
  v.nvim_command('silent g/^[a-z]\\+[{}]/d')
  v.nvim_win_set_cursor(0, { 1, 0})
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype="mail"
  vim.bo.modifiable = false
end

return nm

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
