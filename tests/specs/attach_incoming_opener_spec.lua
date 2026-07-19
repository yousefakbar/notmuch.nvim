local H = dofile('tests/helpers.lua')

local function attachment()
  return {
    path = '/tmp/doc.pdf',
    part = {
      id = 1,
      content_type = 'application/pdf',
      filename = 'doc.pdf',
      ext = 'pdf',
      disposition = 'attachment',
      size = 123,
    },
    message = { id = 'msg1' },
  }
end

local function expected_system_opener()
  local sysname = vim.uv.os_uname().sysname
  return (sysname == 'Darwin' and 'open')
    or (sysname == 'Linux' and 'xdg-open')
    or (sysname:match('Windows') and 'start')
    or 'xdg-open'
end

local function with_open_mocks(mocks, fn)
  local old_ui_open = vim.ui.open
  local old_system = vim.system
  local old_executable = vim.fn.executable
  local old_notify = vim.notify

  if mocks.ui_open_set then
    vim.ui.open = mocks.ui_open
  end
  if mocks.system then
    vim.system = mocks.system
  end
  if mocks.executable then
    vim.fn.executable = mocks.executable
  end
  if mocks.notify then
    vim.notify = mocks.notify
  end

  local ok, err = pcall(fn)

  vim.ui.open = old_ui_open
  vim.system = old_system
  vim.fn.executable = old_executable
  vim.notify = old_notify

  if not ok then error(err, 0) end
end

return {
  {
    name = 'attach.incoming.opener.open uses vim.ui.open default opener when available',
    run = function()
      local opener = require('notmuch.attach.incoming.opener')
      local opened

      with_open_mocks({
        ui_open_set = true,
        ui_open = function(path)
          opened = path
          return { pid = 123 }, nil
        end,
        system = function()
          error('vim.system should not be called when vim.ui.open succeeds')
        end,
      }, function()
        local ok, err = opener.open(attachment())
        H.eq(true, ok)
        H.eq(nil, err)
        H.eq('/tmp/doc.pdf', opened)
      end)
    end,
  },
  {
    name = 'attach.incoming.opener.open falls back to command when vim.ui.open is unavailable',
    run = function()
      local opener = require('notmuch.attach.incoming.opener')
      local captured_cmd, captured_opts

      with_open_mocks({
        ui_open_set = true,
        ui_open = nil,
        executable = function()
          return 1
        end,
        system = function(cmd, opts)
          captured_cmd = cmd
          captured_opts = opts
        end,
      }, function()
        local ok, err = opener.open(attachment())
        H.eq(true, ok)
        H.eq(nil, err)
        H.same({ expected_system_opener(), '/tmp/doc.pdf' }, captured_cmd)
        H.same({ detach = true }, captured_opts)
      end)
    end,
  },
  {
    name = 'attach.incoming.opener.open falls back to command when vim.ui.open returns an error',
    run = function()
      local opener = require('notmuch.attach.incoming.opener')
      local captured_cmd

      with_open_mocks({
        ui_open_set = true,
        ui_open = function()
          return nil, 'ui failed'
        end,
        executable = function()
          return 1
        end,
        system = function(cmd)
          captured_cmd = cmd
        end,
      }, function()
        local ok, err = opener.open(attachment())
        H.eq(true, ok)
        H.eq(nil, err)
        H.same({ expected_system_opener(), '/tmp/doc.pdf' }, captured_cmd)
      end)
    end,
  },
  {
    name = 'attach.incoming.opener.open applies user replacement rules',
    run = function()
      local opener = require('notmuch.attach.incoming.opener')
      local captured_cmd, captured_opts

      with_open_mocks({
        ui_open_set = true,
        ui_open = function()
          error('replaced system rule should not call default vim.ui.open handler')
        end,
        executable = function(cmd)
          return cmd == 'custom-open' and 1 or 0
        end,
        system = function(cmd, opts)
          captured_cmd = cmd
          captured_opts = opts
        end,
      }, function()
        local ok, err = opener.open(attachment(), {
          rules = {
            replace = {
              system = {
                name = 'system',
                match = '*',
                command = { 'custom-open', '$path' },
                detach = true,
              },
            },
          },
        })

        H.eq(true, ok)
        H.eq(nil, err)
        H.same({ 'custom-open', '/tmp/doc.pdf' }, captured_cmd)
        H.same({ detach = true }, captured_opts)
      end)
    end,
  },
  {
    name = 'attach.incoming.opener.open reports unavailable commands',
    run = function()
      local opener = require('notmuch.attach.incoming.opener')
      local note

      with_open_mocks({
        ui_open_set = true,
        ui_open = nil,
        executable = function()
          return 0
        end,
        system = function()
          error('vim.system should not be called for unavailable executable')
        end,
        notify = function(msg, level)
          note = { msg = msg, level = level }
        end,
      }, function()
        local ok, err = opener.open(attachment())
        H.eq(false, ok)
        H.contains(err, 'Could not open attachment')
        H.contains(note.msg, 'Could not open attachment')
        H.eq(vim.log.levels.ERROR, note.level)
      end)
    end,
  },
  {
    name = 'attach.incoming.opener.open falls through failed matching rules',
    run = function()
      local opener = require('notmuch.attach.incoming.opener')
      local captured_cmd

      with_open_mocks({
        ui_open_set = true,
        ui_open = nil,
        executable = function(cmd)
          return cmd == 'good-open' and 1 or 0
        end,
        system = function(cmd)
          captured_cmd = cmd
        end,
      }, function()
        local ok, err = opener.open(attachment(), {
          rules = {
            prepend = {
              { name = 'bad', match = '*', command = { 'missing-open', '$path' } },
              { name = 'good', match = '*', command = { 'good-open', '$path' } },
            },
            disable = { 'system' },
          },
        })

        H.eq(true, ok)
        H.eq(nil, err)
        H.same({ 'good-open', '/tmp/doc.pdf' }, captured_cmd)
      end)
    end,
  },
  {
    name = 'attach.incoming.opener.open recovers from handler errors with command fallback',
    run = function()
      local opener = require('notmuch.attach.incoming.opener')
      local captured_cmd

      with_open_mocks({
        executable = function(cmd)
          return cmd == 'good-open' and 1 or 0
        end,
        system = function(cmd)
          captured_cmd = cmd
        end,
      }, function()
        local ok, err = opener.open(attachment(), {
          rules = {
            prepend = {
              {
                name = 'handler-error',
                match = '*',
                handler = function()
                  error('boom')
                end,
                command = { 'good-open', '$path' },
              },
            },
            disable = { 'system' },
          },
        })

        H.eq(true, ok)
        H.eq(nil, err)
        H.same({ 'good-open', '/tmp/doc.pdf' }, captured_cmd)
      end)
    end,
  },
  {
    name = 'attach.incoming.opener.open validates attachment input',
    run = function()
      local opener = require('notmuch.attach.incoming.opener')
      local note

      with_open_mocks({
        notify = function(msg, level)
          note = { msg = msg, level = level }
        end,
      }, function()
        local ok, err = opener.open(nil, {})
        H.eq(false, ok)
        H.contains(err, 'attachment must be a table')
        H.contains(note.msg, 'attachment must be a table')
        H.eq(vim.log.levels.ERROR, note.level)
      end)
    end,
  },
  {
    name = 'attach.incoming.opener.open reports when no rules match',
    run = function()
      local opener = require('notmuch.attach.incoming.opener')
      local note

      with_open_mocks({
        notify = function(msg, level)
          note = { msg = msg, level = level }
        end,
      }, function()
        local ok, err = opener.open(attachment(), {
          rules = {
            prepend = {
              { name = 'txt-only', match = { ext = 'txt' }, command = { 'open-text', '$path' } },
            },
            disable = { 'system' },
          },
        })

        H.eq(false, ok)
        H.contains(err, 'No open rule matched attachment')
        H.contains(note.msg, 'No open rule matched attachment')
        H.eq(vim.log.levels.ERROR, note.level)
      end)
    end,
  },
}
