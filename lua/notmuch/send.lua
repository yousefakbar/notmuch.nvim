local s = {}
local u = require('notmuch.util')
local m = require('notmuch.mime')
local v = vim.api

local config = require('notmuch.config')

-- Prompt confirmation for sending an email
--
-- This function utilizes vim's builtin `confirm()` to prompt the user and
-- confirm the action of sending an email. This is applicable for sending newly
-- composed mails or replies by passing the mail file path.
--
-- @param filename string: path to the email message you would like to send
--
-- @usage
--   -- See reply() or compose()
--   vim.keymap.set('n', '<C-c><C-c>', function()
--     confirm_sendmail(reply_filename)
--   end, { buffer = true })
local confirm_sendmail = function()
  local choice = v.nvim_call_function('confirm', {
    'Send email?',
    '&Yes\n&No',
    2 -- Default to no
  })

  if choice == 1 then
    return true
  else
    return false
  end
end

--- Builds plain text msg from contents into single-part MIME message of main
--- msg buffer and outputs it in place.
---
--- If the composed email has no attachments, it makes more sense (cheaper and
--- more idiomatic) to send as a single part (not MIME `multipart/mixed`) of
--- type `text/plain; charset=UTF-8`.
---
--- @param buf integer: buffer ID of the message compose file
local build_plain_msg = function(buf)
  local main_lines = v.nvim_buf_get_lines(buf, 0, -1, false)

  -- Extract attributes and remove from main message buffer `buf`
  local attributes, msg = m.get_msg_attributes(main_lines)
  v.nvim_buf_set_lines(buf, 0, -1, false, msg)
  vim.cmd.write({ bang = true })

  -- Build MIME single-part email:
  -- - Header
  -- - MIME headers
  -- - Blank line
  -- - Body
  local plain_msg = {}

  -- Add email headers (To, From, Subject, etc.)
  for key, value in pairs(attributes) do
    table.insert(plain_msg, key .. ": " .. value)
  end

  -- Add MIME headers (required for UTF-8 support per RFC2045)
  table.insert(plain_msg, "MIME-Version: 1.0")
  table.insert(plain_msg, "Content-Type: text/plain; charset=utf-8")
  table.insert(plain_msg, "Content-Transfer-Encoding: 8bit")

  -- Add blank line separator (required by RFC5322)
  table.insert(plain_msg, "")

  -- Add message body
  for _, line in ipairs(msg) do
    table.insert(plain_msg, line)
  end

  -- Write complete email to file
  v.nvim_buf_set_lines(buf, 0, -1, false, plain_msg)
  vim.cmd.write({ bang = true })
end

-- Builds mime msg from contents of main msg buffer and attachment list
local build_mime_msg_from_attachments = function(buf, attachment_paths, message_filename)
  local main_lines = v.nvim_buf_get_lines(buf, 0, -1, false)

  -- Extract headers and body (read-only operation)
  local attributes, msg = m.get_msg_attributes(main_lines)

  -- VALIDATE attachments BEFORE modifying buffer/file
  local attachments = m.create_mime_attachments(attachment_paths)

  -- Safe to modify buffer now
  v.nvim_buf_set_lines(buf, 0, -1, false, msg)
  vim.cmd.write({ bang = true })

  -- Build MIME parts: main body + attachments
  local mimes = { {
    file = message_filename,
    type = "text/plain; charset=utf-8",
  } }

  for _, attachment in ipairs(attachments) do
    table.insert(mimes, attachment)
  end

  local mime_table = {
    version = "Mime-Version: 1.0",
    type = "multipart/mixed",
    encoding = "8 bit",
    attributes = attributes,
    mime = mimes,
  }

  local mime_msg = m.make_mime_msg(mime_table)
  v.nvim_buf_set_lines(buf, 0, -1, false, mime_msg)

  vim.cmd.write({ bang = true })
end

-- Send a completed message
--
-- This function takes a file containing a completed message and send it to the
-- recipient(s) using `msmtp`. Typically you will invoke this function after
-- confirming from a reply or newly composed email message. The invocation of
-- `msmtp` determines by itself the recipient and the sender.
--
-- If the configuration `config.options.logfile` is set, then it invokes
-- `msmtp` with logging capability to that file. Otherwise, it logs to
-- temporary file.
--
-- @param filename string: path to the email message you would like to send
--
-- @return string: The log message provided by `msmtp`
--
-- @usage
--   require('notmuch.send').sendmail('/tmp/my_new_email.eml')
s.sendmail = function(filename)
  -- Read the email file content
  local content = vim.fn.readfile(filename)

  -- Build msmtp command with optional logfile
  local cmd = { 'msmtp', '-t', '--read-envelope-from' }
  if config.options.logfile then
    table.insert(cmd, '--logfile=' .. config.options.logfile)
  end

  local output = vim.fn.system(cmd, content)
  local exit_code = vim.v.shell_error

  -- Check for errors
  if exit_code ~= 0 then
    vim.notify(
      '❌ Failed to send email\n' .. vim.trim(output),
      vim.log.levels.ERROR
    )
    return false
  end

  -- Success
  vim.notify('✅ Email sent successfully', vim.log.levels.INFO)
  return true
end

-- Reply to an email message
--
-- This function uses `notmuch reply` to generate and prepare a reply draft to a
-- message by scanning for the `id` of the message you want to reply to. The
-- draft file will be stored in `tmp/` and a keymap (default `<C-c><C-c>`) to
-- allow sending directly from within nvim
--
-- @usage
--   -- Typically you would just press `R` on a message in a thread
--   require('notmuch.send').reply()
s.reply = function()
  -- Get msg id of the mail to be replied to
  local id = u.find_cursor_msg_id()
  if not id then return end

  -- Create new draft mail to hold reply
  local sanitized_id = id:gsub('/', '-')
  local reply_filename = '/tmp/reply-' .. sanitized_id .. '.eml'

  -- Create and edit buffer containing reply file
  local buf = v.nvim_create_buf(true, false)
  v.nvim_win_set_buf(0, buf)
  vim.cmd.edit(reply_filename)

  -- If first time replying, generate draft. Otherwise, no need to duplicate
  if not u.file_exists(reply_filename) then
    vim.cmd('silent 0read! notmuch reply id:' .. id)
  end

  vim.bo.bufhidden = "wipe"          -- Automatically wipe buffer when closed
  v.nvim_win_set_cursor(0, { 1, 0 }) -- Return cursor to top of file

  -- Initialize attachments variable
  -- Sample "attachment" object:
  --   {
  --     file = 'path/to/attachment',
  --     size = uv.fs_stat(),
  --     mime = mime.get_mime_type()
  --     valid = true or false -- u.validate_attachment_file()
  --   }
  vim.api.nvim_buf_set_var(buf, 'notmuch_attachments', {})

  -- Define commands for attachment management (attach_cmd.lua)
  local attach_cmd = require('notmuch.attach_cmd')

  v.nvim_buf_create_user_command(buf, 'Attach', attach_cmd.attach_handler(buf), {
    nargs = 1,
    complete = 'file',
    desc = 'Add file to email attachments'
  })

  v.nvim_buf_create_user_command(buf, 'AttachRemove', attach_cmd.remove_handler(buf), {
    nargs = 1,
    complete = attach_cmd.remove_completion(buf),
    desc = 'Remove attachment by filepath'
  })

  v.nvim_buf_create_user_command(buf, 'AttachList', attach_cmd.list_handler(buf), {
    nargs = 0,
    desc = 'List current email attachments'
  })

  -- Set keymap for sending
  vim.keymap.set('n', config.options.keymaps.sendmail, function()
    if confirm_sendmail() then
      local attachments = v.nvim_buf_get_var(buf, 'notmuch_attachments')

      if #attachments == 0 then
        build_plain_msg(buf)
      else
        build_mime_msg_from_attachments(buf, attachments, reply_filename)
      end

      s.sendmail(reply_filename)
    end
  end, { buffer = true })
end

-- Compose a new email
--
-- This function creates a new email for the user to edit, with the standard
-- message headers and body. The mail content is stored in `/tmp/` so the user
-- can come back to it later if needed.
--
-- @param to string: recipient address (optionaal argument)
--
-- @usage
--   -- Typically you can run this with `:ComposeMail` or pressing `C`
--   require('notmuch.send').compose()
s.compose = function(to)
  to = to or ''
  local compose_filename = '/tmp/compose.eml'

  -- TODO: Add ability to modify default body message and signature
  local headers = {
    'From: ' .. config.options.from,
    'To: ' .. to,
    'Cc: ',
    'Subject: ',
    '',
    'Message body goes here. Add attachments with "' ..
    config.options.keymaps.attachment_window .. '". Send with "' .. config.options.keymaps.sendmail .. '".',
  }

  -- Create new buffer
  local buf = v.nvim_create_buf(true, false)
  v.nvim_win_set_buf(0, buf)
  vim.cmd.edit(compose_filename)

  -- Populate with header fields (date, to, subject)
  v.nvim_buf_set_lines(buf, 0, -1, false, headers)

  -- Initialize buffer variable to track message attachments
  v.nvim_buf_set_var(buf, 'notmuch_attachments', {})

  -- Define commands for attachment management (attach_cmd.lua)
  local attach_cmd = require('notmuch.attach_cmd')

  v.nvim_buf_create_user_command(buf, 'Attach', attach_cmd.attach_handler(buf), {
    nargs = 1,
    complete = 'file',
    desc = 'Add file to email attachments'
  })

  v.nvim_buf_create_user_command(buf, 'AttachRemove', attach_cmd.remove_handler(buf), {
    nargs = 1,
    complete = attach_cmd.remove_completion(buf),
    desc = 'Remove attachment by filepath'
  })

  v.nvim_buf_create_user_command(buf, 'AttachList', attach_cmd.list_handler(buf), {
    nargs = 0,
    desc = 'List current email attachments'
  })

  -- Keymap for sending the email
  vim.keymap.set('n', config.options.keymaps.sendmail, function()
    if confirm_sendmail() then
      local attachments = v.nvim_buf_get_var(buf, 'notmuch_attachments')

      if #attachments == 0 then
        build_plain_msg(buf)
      else
        build_mime_msg_from_attachments(buf, attachments, compose_filename)
      end

      s.sendmail(compose_filename)
    end
  end, { buffer = true })
end

return s
