local a = {}
local v = vim.api

local function find_cursor_msg_id()
  local n = v.nvim_win_get_cursor(0)[1] + 1
  local line = nil
  local id = nil
  while n ~= 1 do
    line = vim.fn.getline(n)
    if string.match(line, '^id:%S+ {{{$') ~= nil then
      id = string.match(line, '%S+', 4)
      return id
    end
    n = n - 1
  end
  return nil
end

-- TODO generalize this: <dontcare>/<extension part
a.view_attachment_part = function()
  local n = v.nvim_win_get_cursor(0)[1]
  local l = vim.fn.getline(n)
  local id = string.match(v.nvim_buf_get_name(0), 'id:%C+')
  if string.match(l, 'text/html') ~= nil then
    os.execute('notmuch show --exclude=false --part=' .. n .. ' ' .. id .. '>/tmp/notmuch.html')
    os.execute('open /tmp/notmuch.html')
  elseif string.match(l, 'application/pdf') ~= nil then
    os.execute('notmuch show --exclude=false --part=' .. n .. ' ' .. id .. '>/tmp/notmuch.pdf')
    os.execute('open /tmp/notmuch.pdf')
  elseif string.match(l, 'image/jpeg') ~= nil then
    os.execute('notmuch show --exclude=false --part=' .. n .. ' ' .. id .. '>/tmp/notmuch.jpeg')
    os.execute('open /tmp/notmuch.jpeg')
  else
    os.execute('notmuch show --exclude=false --part=' .. n .. ' ' .. id .. '>/tmp/notmuch.txt')
    os.execute('open /tmp/notmuch.txt')
  end
end

-- TODO generalize this: <dontcare>/<extension part
a.save_attachment_part = function()
  local n = v.nvim_win_get_cursor(0)[1]
  local l = vim.fn.getline(n)
  local id = string.match(v.nvim_buf_get_name(0), 'id:%C+')
  if string.match(l, 'text/html') ~= nil then
    os.execute('notmuch show --exclude=false --part=' .. n .. ' ' .. id .. '>notmuch.html')
    print('saved html part to notmuch.html')
  elseif string.match(l, 'application/pdf') ~= nil then
    os.execute('notmuch show --exclude=false --part=' .. n .. ' ' .. id .. '>notmuch.pdf')
    print('saved html part to notmuch.pdf')
  elseif string.match(l, 'image/jpeg') ~= nil then
    os.execute('notmuch show --exclude=false --part=' .. n .. ' ' .. id .. '>notmuch.jpeg')
    os.execute('open notmuch.jpeg')
  else
    os.execute('notmuch show --exclude=false --part=' .. n .. ' ' .. id .. '>notmuch.txt')
    print('saved html part to notmuch.txt')
  end
end

a.get_attachments_from_cursor_msg = function()
  local id = find_cursor_msg_id()
  if id == nil then return nil end
  v.nvim_command('belowright 8new')
  v.nvim_buf_set_name(0, 'id:' .. id)
  vim.bo.buftype = "nofile"
  v.nvim_command('silent 0read! notmuch show --part=1 --exclude=false id:' .. id .. ' | grep -E "^Content-Type:"')
  v.nvim_win_set_cursor(0, { 1, 0 })
  v.nvim_buf_set_lines(0, -2, -1, true, {})
  vim.bo.filetype="notmuch-attach"
  vim.bo.modifiable = false
end

a.get_urls_from_cursor_msg = function()
  local id = find_cursor_msg_id()
  if id == nil then return nil end
  v.nvim_command('YT "notmuch show id:' .. id .. ' | urlextract"')
end

return a

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
