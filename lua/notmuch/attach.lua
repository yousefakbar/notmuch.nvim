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

local function show_github_patch(link)
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, link)
  v.nvim_win_set_buf(0, buf)
  v.nvim_command("silent 0read! curl -Ls " .. link)
  v.nvim_win_set_cursor(0, { 1, 0})
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "gitsendemail"
  vim.bo.modifiable = false
end

-- TODO generalize this: <dontcare>/<extension part
a.view_attachment_part = function()
  local f = a.save_attachment_part('/tmp')
  os.execute('open ' .. f)
end

-- TODO generalize this: <dontcare>/<extension part
a.save_attachment_part = function(savedir)
  if savedir then dir = savedir else dir = '.' end
  local n = v.nvim_win_get_cursor(0)[1]
  local l = vim.fn.getline(n)
  local id = string.match(v.nvim_buf_get_name(0), 'id:%C+')
  local ext = string.match(l, '%w+/(%w+)')
  if ext == 'plain' then ext = 'txt' end
  local f = dir .. '/notmuch.' .. ext
  os.execute('notmuch show --exclude=false --part=' .. n .. ' ' .. id .. '>' .. f)
  print('Saved to: ' .. f)
  return f
end

a.get_attachments_from_cursor_msg = function()
  local id = find_cursor_msg_id()
  if id == nil then return nil end
  v.nvim_command('belowright 8new')
  v.nvim_buf_set_name(0, 'id:' .. id)
  vim.bo.buftype = "nofile"
  v.nvim_command('silent 0read! notmuch show --part=0 --exclude=false id:' .. id .. ' | grep -E "^Content-[Tt]ype:"')
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

a.follow_github_patch = function(line)
  -- https://github.com/neomutt/neomutt/pull/2774.patch
  local link = string.match(line, 'http[s]://github%.com/.+/.+/pull/%d+%.patch')
  if link == nil then
    return nil
  end
  local bufno = vim.fn.bufnr(link)
  if bufno ~= -1 then
    v.nvim_win_set_buf(0, bufno)
  else
    show_github_patch(link)
  end
end

return a

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
