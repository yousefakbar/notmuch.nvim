local s = {}
local u = require('notmuch.util')
local v = vim.api

local config = require('notmuch.config')

-- Save a completed message in the sent folder
--
-- This inserts the email stored under `filename` in the notmuch library under
-- `folder`, and removes the tags `inbox` and `unread`, which are automatically
-- added by `notmuch insert`.
--
-- @param filename string: path to the email message you would like to send
--
-- @param folder string: folder name of location where to store the email
s.savemail = function(filename, folder)
  os.execute("notmuch insert --folder=" .. folder .. " -inbox -unread < " .. filename)
end

-- Prompt confirmation for sending an email
--
-- This function utilizes vim's builtin `confirm()` to prompt the user and
-- confirm the action of sending an email. This is applicable for sending newly
-- composed mails or replies by passing the mail file path.
--
-- If the user specified a sent folder in the configuration
-- `config.options.sent_folder`, then this function will prepend two header
-- fields to the email before it is sent: `Date` and `Message-ID`. The former
-- is set to now, the latter to a random uuid @localhost. Then it sends the
-- email. On successful transmission, this function calls `savemail` to insert
-- the email in the notmuch library. If we would not add these header fields,
-- then the datetime will be unspecified, and the email will not be correctly
-- assigned to the thread it belongs to.
--
-- This function also parses the log message returned by `s.sendmail` to
-- determine if the message transmission was successful or not.
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
    if config.options.sent_folder then
      local date_line = "Date: " .. vim.fn.system("date -R"):gsub("\n", "")
      v.nvim_buf_set_lines(0, 0, 0, false, { date_line })
      local messageid_line = "Message-ID: " .. vim.fn.system('echo "<$(uuidgen)@localhost>"'):gsub("\n", "")
      v.nvim_buf_set_lines(0, 0, 0, false, { messageid_line })
    end
    vim.cmd.write()
    local log_message = s.sendmail(filename)
    local smtpstatus = log_message:match("smtpstatus=([^ ]*)")
    local exitcode = log_message:match("exitcode=([^ ]*)")
    if exitcode == "EX_OK" and smtpstatus == "250" then
      vim.notify("📨 email sent successfully")
      if config.options.sent_folder then
        s.savemail(filename, config.options.sent_folder)
      end
    else
      vim.notify("❌ failed to send email: " .. smtpstatus, vim.log.levels.ERROR)
    end
  end
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
  local logfile = config.options.logfile or os.tmpname()
  os.execute("msmtp -t --read-envelope-from --logfile=" .. logfile .. " <" .. filename)
  return vim.fn.system("tail -1 " .. logfile):gsub("\n", "")
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
    'From: ' .. config.options.from,
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
