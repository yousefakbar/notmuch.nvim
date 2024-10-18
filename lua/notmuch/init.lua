local nm = {}
local v = vim.api

local default_cmd = 'mbsync -a'
if vim.g.NotmuchMaildirSyncCmd == nil then vim.g.NotmuchMaildirSyncCmd = default_cmd end

local default_open_cmd = 'xdg-open'
if vim.fn.has('mac') == 1 then default_open_cmd = 'open' end
if vim.fn.has('wsl') == 1 then default_open_cmd = 'wsl-open' end
if vim.g.NotmuchOpenCmd == nil then vim.g.NotmuchOpenCmd = default_open_cmd end

local default_send_cmd = 'msmtp -t'
if vim.g.NotmuchMailSendCmd == nil then vim.g.NotmuchMailSendCmd = default_send_cmd end

local default_compose_file = '/tmp/notmuch.nvim.compose.eml'
if vim.g.NotmuchComposeFile == nil then vim.g.NotmuchComposeFile = default_compose_file end

local db_path = os.getenv("HOME") .. '/Mail'
if vim.g.NotmuchDBPath == nil then vim.g.NotmuchDBPath = db_path end

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
    elseif string.match(line, '^header}') ~= nil then
      v.nvim_buf_set_lines(buf, lineno-1, lineno, true, { '' })
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

local function show_all_tags()
  local db = require'notmuch.cnotmuch'(vim.g.NotmuchDBPath, 0)
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "Tags")
  v.nvim_win_set_buf(0, buf)
  v.nvim_buf_set_lines(buf, 0, 0, true, db.get_all_tags())
  v.nvim_win_set_cursor(0, { 1, 0})
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-hello"
  vim.bo.modifiable = false
  db.close()
end

nm.count = function(search)
  local db = require'notmuch.cnotmuch'(vim.g.NotmuchDBPath, 0)
  local q = db.create_query(search)
  local count_messages = q.count_messages()
  db.close()
  return count_messages
end

nm.search_terms = function(search)
  local num_threads_found = 0
  if search == '' then
    return nil
  elseif string.match(search, '^thread:%S+$') ~= nil then
    nm.show_thread(search)
    return true
  end
  local bufno = vim.fn.bufnr(search)
  if bufno ~= -1 then
    v.nvim_win_set_buf(0, bufno)
    return true
  end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, search)
  v.nvim_win_set_buf(0, buf)
  v.nvim_command("silent 0read! notmuch search " .. search)
  v.nvim_win_set_cursor(0, { 1, 0 })
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-threads"
  vim.bo.modifiable = false
  if vim.fn.getline(1) ~= '' then num_threads_found = vim.fn.line('$') end
  print('Found ' .. num_threads_found .. ' threads')
end

nm.show_thread = function(s)
  local threadid = ''
  if s == nil then
    local line = v.nvim_get_current_line()
    threadid = string.match(line, "[0-9a-z]+", 7)
  else
    threadid = string.match(s, "[0-9a-z]+", 7)
  end
  local bufno = vim.fn.bufnr('thread:' .. threadid)
  if bufno ~= -1 then
    v.nvim_win_set_buf(0, bufno)
    return true
  end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "thread:" .. threadid)
  v.nvim_win_set_buf(0, buf)
  --v.nvim_command("silent 0read! notmuch show --exclude=false thread:" .. threadid .. " | sed 's///g'")
  v.nvim_command("silent 0read! notmuch show --exclude=false thread:" .. threadid .. " | col")
  process_msgs_in_thread(buf)
  v.nvim_win_set_cursor(0, { 1, 0})
  v.nvim_buf_set_lines(buf, -3, -1, true, {})
  vim.bo.filetype="mail"
  vim.bo.modifiable = false
end

nm.refresh_search_buffer = function()
  local search = string.match(v.nvim_buf_get_name(0), '%a+:%C+')
  v.nvim_command('bwipeout')
  nm.search_terms(search)
end

nm.refresh_thread_buffer = function()
  local thread = string.match(v.nvim_buf_get_name(0), 'thread:%C+')
  v.nvim_command('bwipeout')
  nm.show_thread(thread)
end

nm.refresh_hello_buffer = function()
  v.nvim_command('bwipeout')
  show_all_tags()
end

nm.notmuch_hello = function()
  local bufno = vim.fn.bufnr('Tags')
  if bufno ~= -1 then
    v.nvim_win_set_buf(0, bufno)
  else
    show_all_tags()
  end
  print("Welcome to Notmuch.nvim! Choose a tag to search it.")
end

nm.send = function()
	-- Ask for confirmation
	local confirm = vim.fn.input("Send email? (y/n): ")
	if confirm:lower() ~= "y" then
		print("Email send canceled.")
		return
	end

	-- Save the buffer content
	vim.cmd("write!")

	-- Use msmtp or sendmail to send email
	local ret = vim.fn.system(vim.g.NotmuchMailSendCmd .. " < " .. vim.g.NotmuchComposeFile)

	if vim.v.shell_error ~= 0 then
		print("Failed to send email: " .. ret)
	else
		print("Email sent successfully!")
	end
end

-- Open a new buffer for composing email
nm.compose = function()
	local buf = v.nvim_create_buf(true, true)
	v.nvim_win_set_buf(0, buf)
	v.nvim_buf_set_name(buf, vim.g.NotmuchComposeFile)
	vim.bo.filetype = "mail"
	vim.bo.buftype = ""
	vim.bo.modifiable = true
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {
		"To: ",
		"Cc: ",
		"Subject: ",
		"",
		"Hello, message starts here ...",
		"",
	})
end

return nm

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
