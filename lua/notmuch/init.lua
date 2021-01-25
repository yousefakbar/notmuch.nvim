local nm = {}
local v = vim.api
local u = require'notmuch.util'

local function indent_depth(buf, lineno, depth)
  local line = vim.fn.getline(lineno)
  local s = ''
  for i=0,depth-1 do s = '────' .. s end
  v.nvim_buf_set_lines(buf, lineno-1, lineno, true, { s .. line })
end

local function process_msgs_in_thread(buf)
  local msg = {}
  local lineno = 1
  local last = vim.fn.line('$')
  while lineno <= last do
    local line = vim.fn.getline(lineno)
    if string.match(line, "^message{") ~= nil then
      msg.id = string.match(line, 'id:%S+')
      msg.depth = tonumber(string.match(string.match(line, 'depth:%d+'), '%d+'))
      msg.filename = string.match(line, 'filename:%C+')
      v.nvim_buf_set_lines(buf, lineno-1, lineno, true, {})
      lineno = lineno - 1
      last = last - 1
    elseif string.match(line, '^header{') ~= nil then
      v.nvim_buf_set_lines(buf, lineno-1, lineno, true, {})
      indent_depth(buf, lineno, msg.depth)
      line = vim.fn.getline(lineno)
      v.nvim_buf_set_lines(buf, lineno-1, lineno, true, { line, msg.id .. ' {{{' })
    elseif string.match(line, '^Subject:') ~= nil then
      lineno = lineno + 2
      last = last + 1
    elseif string.match(line, '^message}') ~= nil then
      v.nvim_buf_set_lines(buf, lineno-1, lineno, true, { '}}}', '' })
      lineno = lineno + 1
      last = last + 1
    elseif string.match(line, '^%a+[{}]') ~= nil then
      v.nvim_buf_set_lines(buf, lineno-1, lineno, true, {})
      lineno = lineno - 1
      last = last - 1
    end
    lineno = lineno + 1
  end
end

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

nm.show_thread = function()
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, "[0-9a-z]+", 7)
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "thread:" .. threadid)
  v.nvim_win_set_buf(0, buf)
  v.nvim_command("silent 0read! notmuch show --exclude=false thread:" .. threadid .. " | sed 's///g'")
  process_msgs_in_thread()
  v.nvim_win_set_cursor(0, { 1, 0})
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  --vim.wo.foldmethod="marker"
  vim.bo.filetype="mail"
  vim.bo.modifiable = false
end

return nm

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
