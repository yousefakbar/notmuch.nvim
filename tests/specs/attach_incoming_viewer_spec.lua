local H = dofile('tests/helpers.lua')

local function attachment(part, path)
  return {
    path = path or '/tmp/doc.pdf',
    part = vim.tbl_extend('force', {
      id = 1,
      content_type = 'application/pdf',
      filename = 'doc.pdf',
      ext = 'pdf',
      disposition = 'attachment',
      size = 123,
    }, part or {}),
    message = { id = 'msg1' },
  }
end

local function with_view_mocks(mocks, fn)
  local old_executable = vim.fn.executable
  local old_system = vim.system

  if mocks.executable then
    vim.fn.executable = mocks.executable
  end
  if mocks.system then
    vim.system = mocks.system
  end

  local ok, err = pcall(fn)

  vim.fn.executable = old_executable
  vim.system = old_system

  if not ok then error(err, 0) end
end

return {
  {
    name = 'attach.incoming.viewer.view uses first available successful command',
    run = function()
      local viewer = require('notmuch.attach.incoming.viewer')
      local captured_cmd, captured_opts

      with_view_mocks({
        executable = function(cmd)
          return cmd == 'pdftotext' and 1 or 0
        end,
        system = function(cmd, opts)
          captured_cmd = cmd
          captured_opts = opts
          return { wait = function() return { code = 0, stdout = 'pdf text', stderr = '' } end }
        end,
      }, function()
        local result, err = viewer.view(attachment())

        H.eq(nil, err)
        H.eq('pdf text', result.content)
        H.eq('text', result.filetype)
        H.eq('doc.pdf', result.title)
        H.eq('pdf', result.rule)
        H.eq('pdftotext', result.source)
        H.same({ 'pdftotext', '-layout', '/tmp/doc.pdf', '-' }, captured_cmd)
        H.same({ text = true }, captured_opts)
      end)
    end,
  },
  {
    name = 'attach.incoming.viewer.view falls back through failed command chains',
    run = function()
      local viewer = require('notmuch.attach.incoming.viewer')
      local calls = {}

      with_view_mocks({
        executable = function(cmd)
          return (cmd == 'pdftotext' or cmd == 'mutool') and 1 or 0
        end,
        system = function(cmd)
          calls[#calls + 1] = cmd
          local tool = cmd[1]
          return {
            wait = function()
              if tool == 'pdftotext' then
                return { code = 1, stdout = '', stderr = 'pdf failed' }
              end
              return { code = 0, stdout = 'mutool text', stderr = '' }
            end,
          }
        end,
      }, function()
        local result, err = viewer.view(attachment())

        H.eq(nil, err)
        H.eq('mutool text', result.content)
        H.eq('mutool', result.source)
        H.same({ 'pdftotext', '-layout', '/tmp/doc.pdf', '-' }, calls[1])
        H.same({ 'mutool', 'draw', '-F', 'txt', '/tmp/doc.pdf' }, calls[2])
      end)
    end,
  },
  {
    name = 'attach.incoming.viewer.view returns matched rule fallback when tools are missing',
    run = function()
      local viewer = require('notmuch.attach.incoming.viewer')

      with_view_mocks({
        executable = function()
          return 0
        end,
        system = function()
          error('vim.system should not be called when tools are unavailable')
        end,
      }, function()
        local result, err = viewer.view(attachment())

        H.eq(nil, err)
        H.contains(result.content, 'PDF file')
        H.contains(result.content, 'pdftotext')
        H.eq('text', result.filetype)
        H.eq('doc.pdf', result.title)
        H.eq('pdf', result.rule)
        H.eq('fallback', result.source)
      end)
    end,
  },
  {
    name = 'attach.incoming.viewer.view normalizes handler table results',
    run = function()
      local viewer = require('notmuch.attach.incoming.viewer')
      local result, err = viewer.view(attachment(), {
        rules = {
          prepend = {
            {
              name = 'custom',
              match = '*',
              handler = function()
                return {
                  content = 'custom content',
                  filetype = 'markdown',
                  title = 'Custom Title',
                }
              end,
            },
          },
        },
      })

      H.eq(nil, err)
      H.eq('custom content', result.content)
      H.eq('markdown', result.filetype)
      H.eq('Custom Title', result.title)
      H.eq('custom', result.rule)
      H.eq('handler', result.source)
    end,
  },
  {
    name = 'attach.incoming.viewer.view recovers from handler errors with commands',
    run = function()
      local viewer = require('notmuch.attach.incoming.viewer')
      local captured_cmd

      with_view_mocks({
        executable = function(cmd)
          return cmd == 'pdftotext' and 1 or 0
        end,
        system = function(cmd)
          captured_cmd = cmd
          return { wait = function() return { code = 0, stdout = 'command content', stderr = '' } end }
        end,
      }, function()
        local result, err = viewer.view(attachment(), {
          rules = {
            prepend = {
              {
                name = 'custom-pdf',
                match = { ext = 'pdf' },
                handler = function()
                  error('boom')
                end,
                commands = {
                  { 'pdftotext', '$path', '-' },
                },
                filetype = 'text',
                fallback = 'custom fallback',
              },
            },
          },
        })

        H.eq(nil, err)
        H.eq('command content', result.content)
        H.eq('custom-pdf', result.rule)
        H.eq('pdftotext', result.source)
        H.same({ 'pdftotext', '/tmp/doc.pdf', '-' }, captured_cmd)
      end)
    end,
  },
  {
    name = 'attach.incoming.viewer.view handles text attachments via cat command',
    run = function()
      local viewer = require('notmuch.attach.incoming.viewer')
      local captured_cmd

      with_view_mocks({
        executable = function(cmd)
          return cmd == 'cat' and 1 or 0
        end,
        system = function(cmd)
          captured_cmd = cmd
          return { wait = function() return { code = 0, stdout = 'plain text body', stderr = '' } end }
        end,
      }, function()
        local result, err = viewer.view(attachment({
          content_type = 'text/plain',
          filename = 'note.txt',
          ext = 'txt',
        }, '/tmp/note.txt'))

        H.eq(nil, err)
        H.eq('plain text body', result.content)
        H.eq('text', result.filetype)
        H.eq('note.txt', result.title)
        H.eq('text', result.rule)
        H.eq('cat', result.source)
        H.same({ 'cat', '/tmp/note.txt' }, captured_cmd)
      end)
    end,
  },
  {
    name = 'attach.incoming.viewer.view uses binary fallback when strings is unavailable',
    run = function()
      local viewer = require('notmuch.attach.incoming.viewer')

      with_view_mocks({
        executable = function()
          return 0
        end,
        system = function()
          error('vim.system should not be called when strings is unavailable')
        end,
      }, function()
        local result, err = viewer.view(attachment({
          content_type = 'application/octet-stream',
          filename = 'blob.bin',
          ext = 'bin',
        }, '/tmp/blob.bin'))

        H.eq(nil, err)
        H.contains(result.content, 'Unable to view binary file')
        H.contains(result.content, 'application/octet-stream')
        H.contains(result.content, '/tmp/blob.bin')
        H.eq('binary', result.rule)
        H.eq('fallback', result.source)
      end)
    end,
  },
  {
    name = 'attach.incoming.viewer.view reports no matching rule',
    run = function()
      local viewer = require('notmuch.attach.incoming.viewer')
      local result, err = viewer.view(attachment(), {
        rules = {
          disable = { 'html', 'pdf', 'image', 'office', 'markdown', 'zip', 'tar', 'text', 'binary' },
        },
      })

      H.eq(nil, result)
      H.contains(err, 'No view rule matched attachment')
    end,
  },
  {
    name = 'attach.incoming.viewer.view validates attachment input',
    run = function()
      local viewer = require('notmuch.attach.incoming.viewer')
      local result, err = viewer.view(nil)

      H.eq(nil, result)
      H.contains(err, 'attachment must be a table')
    end,
  },
}
