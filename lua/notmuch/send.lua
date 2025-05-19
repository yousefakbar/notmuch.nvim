local s = {}
local u = require('notmuch.util')
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
local confirm_sendmail = function(filename)
  local choice = v.nvim_call_function('confirm', {
    'Send email?',
    '&Yes\n&No',
    2 -- Default to no
  })

  if choice == 1 then
    vim.cmd.write()
    s.sendmail(filename)
  end
end

-- Send a completed message
--
-- This function takes a file containing a completed message and send it to the
-- recipient(s) using `msmtp`. Typically you will invoke this function after
-- confirming from a reply or newly composed email message
--
-- @param filename string: path to the email message you would like to send
--
-- @usage
--   require('notmuch.send').sendmail('/tmp/my_new_email.eml')
s.sendmail = function(filename)
  os.execute('msmtp -t <' .. filename)
  print('Successfully sent email: ' .. filename)
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
  local reply_filename = '/tmp/reply-' .. id .. '.eml'

  -- Create and edit buffer containing reply file
  local buf = v.nvim_create_buf(true, false)
  v.nvim_win_set_buf(0, buf)
  vim.cmd.edit(reply_filename)

  -- If first time replying, generate draft. Otherwise, no need to duplicate
  if not u.file_exists(reply_filename) then
    vim.cmd('silent 0read! notmuch reply id:' .. id)
  end

  vim.bo.bufhidden = "wipe" -- Automatically wipe buffer when closed
  v.nvim_win_set_cursor(0, { 1, 0 }) -- Return cursor to top of file

  -- Set keymap for sending
  vim.keymap.set('n', config.options.keymaps.sendmail, function()
    confirm_sendmail(reply_filename)
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
    'To: ' .. to,
    'Cc: ',
    'Subject: ',
    '',
    'Message body goes here',
  }

  -- Create new buffer
  local buf = v.nvim_create_buf(true, false)
  v.nvim_win_set_buf(0, buf)
  vim.cmd.edit(compose_filename)

  -- Populate with header fields (date, to, subject)
  v.nvim_buf_set_lines(buf, 0, -1, false, headers)

  -- Keymap for sending the email
  vim.keymap.set('n', config.options.keymaps.sendmail, function()
    confirm_sendmail(compose_filename)
  end, { buffer = true })
end

return s
