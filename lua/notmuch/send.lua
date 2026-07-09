local s = {}

local attach = require('notmuch.attach')
local config = require('notmuch.config')
local m = require('notmuch.mime')
local thread = require('notmuch.thread')
local v = vim.api


-- Prompt the user to confirm sending the current draft.
--
---@return boolean confirmed True when the user selects Yes.
--
---@usage
--   -- See reply() or compose()
--   vim.keymap.set('n', '<C-c><C-c>', function()
--     if confirm_sendmail() then
--       send_draft(buf, draft)
--     end
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

local build_plain_msg_file = function(buf, output_filename)
  local main_lines = v.nvim_buf_get_lines(buf, 0, -1, false)
  local attributes, msg = m.get_msg_attributes(main_lines)
  local plain_msg = {}

  for key, value in pairs(attributes) do
    table.insert(plain_msg, key .. ": " .. value)
  end

  table.insert(plain_msg, "MIME-Version: 1.0")
  table.insert(plain_msg, "Content-Type: text/plain; charset=utf-8")
  table.insert(plain_msg, "Content-Transfer-Encoding: 8bit")
  table.insert(plain_msg, "")

  for _, line in ipairs(msg) do
    table.insert(plain_msg, line)
  end

  return vim.fn.writefile(plain_msg, output_filename) == 0
end

local build_mime_msg_file = function(buf, attachment_paths, output_filename)
  local main_lines = v.nvim_buf_get_lines(buf, 0, -1, false)
  local attributes, msg = m.get_msg_attributes(main_lines)
  local body_filename = vim.fn.tempname() .. '-notmuch-body.txt'

  local ok, err = pcall(function()
    local attachments = m.create_mime_attachments(attachment_paths)

    if vim.fn.writefile(msg, body_filename) ~= 0 then
      error('Failed to write message body temp file: ' .. body_filename)
    end

    local mimes = { {
      file = body_filename,
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
    if vim.fn.writefile(mime_msg, output_filename) ~= 0 then
      error('Failed to write send temp file: ' .. output_filename)
    end
  end)

  if vim.uv.fs_stat(body_filename) then
    vim.fn.delete(body_filename)
  end

  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

local build_send_file = function(buf, attachment_paths)
  local send_filename = vim.fn.tempname() .. '-notmuch-send.eml'
  local ok

  if #attachment_paths == 0 then
    ok = build_plain_msg_file(buf, send_filename)
  else
    ok = build_mime_msg_file(buf, attachment_paths, send_filename)
  end

  if not ok then
    if vim.uv.fs_stat(send_filename) then
      vim.fn.delete(send_filename)
    end
    vim.notify('Failed to build email for sending', vim.log.levels.ERROR)
    return nil
  end

  return send_filename
end

-- Send a completed message through `msmtp` in an interactive terminal split.
--
-- The message file is passed to `msmtp -t --read-envelope-from`. The terminal is
-- kept interactive so `msmtp` can prompt for credentials if needed. Completion is
-- reported asynchronously through optional callbacks.
--
---@param filename string Path to the RFC 5322/MIME message file to send.
---@param opts? { on_success?: fun(), on_failure?: fun(exit_code: integer) } Optional completion callbacks.
---@return boolean ok True when the terminal send job was started, false when the message file is missing.
--
---@usage
--   require('notmuch.send').sendmail('/tmp/my_new_email.eml')
s.sendmail = function(filename, opts)
  opts = opts or {}

  if not vim.uv.fs_stat(filename) then
    vim.notify('❌ Email file not found: ' .. filename, vim.log.levels.ERROR)
    if opts.on_failure then
      opts.on_failure(-1)
    end
    return false
  end

  -- Build msmtp command
  local cmd_parts = { 'msmtp', '-t', '--read-envelope-from' }
  if config.options.logfile then
    table.insert(cmd_parts, '--logfile=' .. vim.fn.shellescape(config.options.logfile))
  end
  local msmtp_cmd = table.concat(cmd_parts, ' ') .. ' <' .. vim.fn.shellescape(filename)

  vim.notify('📤 Sending email via msmtp...', vim.log.levels.INFO)

  -- Open blank terminal first (reliable PTY handling for interactive input)
  vim.cmd('botright 15split | terminal')
  local term_buf = v.nvim_get_current_buf()
  local term_job = vim.b.terminal_job_id

  -- Set up TermClose autocmd BEFORE sending command to avoid race condition
  -- Note: Using pattern='*' instead of buffer=term_buf due to Neovim bug where
  -- buffer-specific TermClose doesn't fire reliably on terminal buffers
  local aug = v.nvim_create_augroup('NotmuchSendmail_' .. term_buf, { clear = true })
  v.nvim_create_autocmd('TermClose', {
    group = aug,
    pattern = '*',
    once = true,
    callback = function(ev)
      -- Only process TermClose for our specific terminal buffer
      if ev.buf ~= term_buf then
        return
      end

      -- Get exit code from v:event.status
      local exit_code = vim.v.event.status or -1

      -- Defer notification on success because of buffer close redraw
      if exit_code == 0 then
        vim.defer_fn(function() vim.notify('✅ Email sent successfully', vim.log.levels.INFO) end, 500)
        if opts.on_success then
          opts.on_success()
        end
      else
        vim.notify('❌ Failed to send email (exit code: ' .. exit_code .. ')', vim.log.levels.ERROR)
        if opts.on_failure then
          opts.on_failure(exit_code)
        end
      end
    end
  })

  -- Send the command to the terminal, then exit shell to trigger TermClose
  vim.fn.chansend(term_job, msmtp_cmd .. ' ; exit\n')

  -- Start in insert mode for immediate interaction (e.g. passphrase prompt)
  vim.cmd('startinsert')

  return true
end

local generate_reply_lines = function(message_id)
  -- Use `notmuch-reply(1)` to generate the reply content
  local result = vim.system({ 'notmuch', 'reply', 'id:' .. message_id }, {
    text = true,
  }):wait()

  -- Validate command success
  if result.code ~= 0 then
    vim.notify('Failed to generate reply:\n' .. (result.stderr or ''), vim.log.levels.ERROR)
    return nil
  end

  -- Return as table of lines to paste in buffer
  return vim.split(result.stdout or '', '\n', { plain = true })
end

local create_reply_draft = function(message_id)
  local lines = generate_reply_lines(message_id)
  if not lines then
    return nil
  end

  return require('notmuch.draft').create_reply_draft(message_id, lines)
end

local send_draft = function(buf, draft)
  -- Saves current draft mail content for good measure
  v.nvim_buf_call(buf, function()
    vim.cmd('silent! write')
  end)

  -- Sync any open attachment scratch buffer and persist attachment metadata
  local attachments = attach.prepare_send(buf)
  if not attachments then
    vim.notify('Failed to persist draft attachment metadata before sending', vim.log.levels.ERROR)
    return false
  end

  -- Build the MIME-compliant email message in TMP directory
  local send_filename = build_send_file(buf, attachments)
  if not send_filename then
    return false
  end

  -- Send with success and failure callbacks
  return s.sendmail(send_filename, {
    on_success = function()
      vim.fn.delete(send_filename)
      local draft_module = require('notmuch.draft')

      if config.options.drafts.delete_sent then
        draft_module.delete_draft(draft)
      else
        draft_module.mark_sent(draft.json_path)
      end
    end,
    on_failure = function()
      vim.fn.delete(send_filename)
    end,
  })
end

local open_draft_buffer = function(draft)
  local draft_filename = draft.eml_path

  -- Create new buffer for the draft
  local buf = v.nvim_create_buf(true, false)
  v.nvim_win_set_buf(0, buf)
  vim.cmd.edit(vim.fn.fnameescape(draft_filename))

  -- Set buffer-local variables for metadata and attachments
  v.nvim_buf_set_var(buf, 'notmuch_draft_json_path', draft.json_path)

  -- Set up draft buffer but keep focus on the draft window/buffer
  local draft_win = v.nvim_get_current_win()
  attach.setup_draft_buffer(buf, draft.metadata.attachments or {}, {
    open_scratch = config.options.drafts.auto_open_attachment_window == true,
  })
  if v.nvim_win_is_valid(draft_win) then
    v.nvim_set_current_win(draft_win)
  end

  -- Keymap for showing attachment_window
  vim.keymap.set('n', config.options.keymaps.attachment_window, function()
    attach.open_scratch(buf)
  end, { buffer = true })

  -- Keymap for sending the email
  vim.keymap.set('n', config.options.keymaps.sendmail, function()
    if confirm_sendmail() then
      send_draft(buf, draft)
    end
  end, { buffer = true })
end

-- Compose a new email
--
-- This function creates a new email for the user to edit, with the standard
-- message headers and body. The mail content is stored in the persistent drafts
-- directory so the user can come back to it later if needed.
--
---@param to? string Optional recipient address list used to prefill the `To:` header.
--
---@usage
--   -- Typically you can run this with `:ComposeMail` or pressing `C`
--   require('notmuch.send').compose()
s.compose = function(to)
  to = to or ''

  -- TODO: Add ability to modify default body message and signature
  local headers = {
    'From: ' .. config.options.from,
    'To: ' .. to,
    'Cc: ',
    'Subject: ',
    '',
    'Message body goes here. Add attachments with "' ..
    config.options.keymaps.attachment_window .. '" or `:AttachOpen`. Send with "' .. config.options.keymaps.sendmail .. '".',
  }

  -- Prepare draft
  local draft = require('notmuch.draft').create_compose_draft(headers)
  if not draft then
    return
  end

  open_draft_buffer(draft)
end

local function format_draft_timestamp(timestamp)
  if not timestamp or timestamp == vim.NIL or timestamp == '' then
    return 'unknown'
  end

  local date, hour, min = timestamp:match('^(%d%d%d%d%-%d%d%-%d%d)T(%d%d):(%d%d)')
  if not date then
    return timestamp
  end

  return string.format('%s %s:%s', date, hour, min)
end

local new_compose_draft_item = {
  action = 'new_compose'
}

local new_reply_draft_item = {
  action = 'new_reply'
}

local format_compose_draft_item = function(item)
  if item.action == 'new_compose' then
    return '➕ Compose new draft'
  end

  local draft = item.draft
  local kind = item.draft.kind
  local timestamp = draft.metadata.updated_at or draft.metadata.created_at
  local updated = format_draft_timestamp(timestamp)
  local subject = draft.subject or '[No subject]'
  local attachments = draft.metadata.attachments or {}
  local attach = #attachments > 0 and ('(📎' .. #attachments .. ')') or ''

  return string.format('[%s] %s - %s %s', kind, updated, subject, attach)
end

local format_reply_draft_item = function(item)
  if item.action == 'new_reply' then
    return '➕ New reply draft'
  end

  local draft = item.draft
  local kind = draft.kind
  local timestamp = draft.metadata.updated_at or draft.metadata.created_at
  local updated = format_draft_timestamp(timestamp)
  local subject = draft.subject or '[No subject]'
  local attachments = draft.metadata.attachments or {}
  local attach = #attachments > 0 and ('(📎' .. #attachments .. ')') or ''

  return string.format('[%s] %s - %s %s', kind, updated, subject, attach)
end

local format_draft_item = function(item)
  if item.action == 'new_compose' then
    return '➕ Compose new draft'
  end

  local draft = item.draft
  local kind = draft.kind or 'draft'
  local timestamp = draft.metadata.updated_at or draft.metadata.created_at
  local updated = format_draft_timestamp(timestamp)
  local subject = draft.subject or '[No subject]'
  local attachments = draft.metadata.attachments or {}
  local attach = #attachments > 0 and ('(📎' .. #attachments .. ')') or ''

  return string.format('[%s] %s - %s %s', kind, updated, subject, attach)
end

local select_reply_draft = function(message_id, drafts)
  local items = { new_reply_draft_item }

  for _, draft in ipairs(drafts) do
    table.insert(items, {
      action = 'open_reply',
      draft = draft,
    })
  end

  vim.ui.select(items, {
    prompt = 'Select reply draft:',
    format_item = format_reply_draft_item,
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == 'new_reply' then
      local draft = create_reply_draft(message_id)
      if draft then
        open_draft_buffer(draft)
      end
      return
    end

    if choice.action == 'open_reply' then
      open_draft_buffer(choice.draft)
    end
  end)
end

-- Reply to an email message
--
-- This function opens or creates a persistent reply draft for the current
-- message. If existing drafts for the message are found, the user can select
-- one or create a new reply draft.
--
---@usage
--   -- Typically you would just press `R` on a message in a thread
--   require('notmuch.send').reply()
s.reply = function()
  local message_id = thread.get_current_message_id()
  if not message_id then
    return
  end

  local drafts = require('notmuch.draft').list_reply_drafts(message_id) or {}

  if #drafts == 0 then
    local draft = create_reply_draft(message_id)
    if draft then
      open_draft_buffer(draft)
    end
    return
  end

  select_reply_draft(message_id, drafts)
end

s.open_compose_draft = function(eml_path)
  local draft = require('notmuch.draft').load_compose_draft(eml_path)
  if not draft then
    return
  end

  open_draft_buffer(draft)
end

s.open_reply_draft = function(eml_path)
  local draft = require('notmuch.draft').load_reply_draft(eml_path)
  if not draft then
    return
  end

  open_draft_buffer(draft)
end

s.select_compose_draft = function()
  local drafts = require('notmuch.draft').list_compose_drafts()
  if not drafts then
    return
  end

  local items = {
    new_compose_draft_item,
  }

  for _, draft in ipairs(drafts) do
    table.insert(items, {
      action = 'open_compose',
      draft = draft,
    })
  end

  vim.ui.select(items, {
    prompt = 'Select compose draft:',
    format_item = format_compose_draft_item,
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == 'new_compose' then
      s.compose()
      return
    end

    if choice.action == 'open_compose' then
      s.open_compose_draft(choice.draft.eml_path)
    end
  end)
end

s.select_draft = function()
  local drafts = require('notmuch.draft').list_all_drafts()
  if not drafts then
    return
  end

  local items = {
    new_compose_draft_item,
  }

  for _, draft in ipairs(drafts) do
    table.insert(items, {
      action = 'open_draft',
      draft = draft,
    })
  end

  vim.ui.select(items, {
    prompt = 'Select draft:',
    format_item = format_draft_item,
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == 'new_compose' then
      s.compose()
      return
    end

    if choice.action == 'open_draft' then
      open_draft_buffer(choice.draft)
    end
  end)
end

return s
