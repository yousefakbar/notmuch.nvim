local H = dofile("tests/helpers.lua")

local function with_current_message_id(id, fn)
  local thread = require("notmuch.thread")
  local old = thread.get_current_message_id
  thread.get_current_message_id = function()
    return id
  end
  local ok, err = pcall(fn)
  thread.get_current_message_id = old
  if not ok then
    error(err, 0)
  end
end

local function attachment_buf(parts, name)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, name or "id:msg1")
  vim.api.nvim_buf_set_var(buf, "mime_parts_list", parts)
  local lines = {
    "Hints: v: View | o: Open | s: Save | q: Close",
    "",
    "?  ID    File                                            Size",
  }
  for _, part in ipairs(parts) do
    lines[#lines + 1] = tostring(part.id)
  end
  lines[#lines + 1] = ""
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function with_system(mock, fn)
  local old_system = vim.system
  vim.system = mock
  local ok, err = pcall(fn)
  vim.system = old_system
  if not ok then
    error(err, 0)
  end
end

local function with_save_extractor(mock, fn)
  local extractor = require("notmuch.attach.incoming.extractor")
  local old_save_to_path = extractor.save_to_path
  extractor.save_to_path = mock
  local ok, err = pcall(fn)
  extractor.save_to_path = old_save_to_path
  if not ok then
    error(err, 0)
  end
end

local function silence_print(fn)
  local old_print = print
  print = function() end
  local ok, err = pcall(fn)
  print = old_print
  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "attach.parts.get_attachments_from_cursor_msg creates formatted attachment list buffer",
    run = function()
      local attach = require("notmuch.attach.parts")
      local command, system_opts
      local json = {
        body = {
          {
            ["content-type"] = "multipart/mixed",
            content = {
              { id = 1, ["content-type"] = "text/plain", ["content-length"] = 12 },
              {
                id = 2,
                ["content-type"] = "multipart/alternative",
                content = {
                  { id = 3, ["content-type"] = "text/html", ["content-length"] = 34 },
                },
              },
              {
                id = 4,
                ["content-type"] = "application/pdf",
                filename = "doc.pdf",
                ["content-disposition"] = "attachment",
                ["content-length"] = 2048,
              },
              {
                id = 5,
                ["content-type"] = "image/png",
                ["content-disposition"] = "inline",
                ["content-length"] = 1024,
              },
            },
          },
        },
      }
      with_system(function(cmd, opts)
        command = cmd
        system_opts = opts
        return {
          wait = function()
            return { code = 0, stdout = vim.json.encode(json), stderr = "" }
          end,
        }
      end, function()
        with_current_message_id("msg1", function()
          attach.get_attachments_from_cursor_msg()
        end)

        H.eq("id:msg1", vim.api.nvim_buf_get_name(0):match("([^/]+)$"))
        H.eq("nofile", vim.bo.buftype)
        H.eq("notmuch-attach", vim.bo.filetype)
        H.eq(false, vim.bo.modifiable)
        H.same({
          "notmuch",
          "show",
          "--exclude=false",
          "--part=0",
          "--format=json",
          "id:msg1",
        }, command)
        H.same({ text = true }, system_opts)

        local parts = vim.api.nvim_buf_get_var(0, "mime_parts_list")
        H.eq(4, #parts)
        H.eq(1, parts[1].id)
        H.eq("inline", parts[1].disposition)
        H.eq(3, parts[2].id)
        H.eq("text/html", parts[2].content_type)
        H.eq(4, parts[3].id)
        H.eq("doc.pdf", parts[3].filename)
        H.eq(5, parts[4].id)
        H.eq("attachment", parts[4].disposition)

        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        H.contains(lines, "Hints: v: View")
        H.contains(lines, "?  ID")
        H.contains(lines, "I  1     body (text/plain)")
        H.contains(lines, "I  3     body (text/html)")
        H.contains(lines, "A  4     doc.pdf")
        H.contains(lines, "A  5     body (image/png)")

        vim.api.nvim_buf_delete(0, { force = true })
      end)
    end,
  },
  {
    name = "attach.parts.get_attachments_from_cursor_msg keeps untrusted message ids in one argv element",
    run = function()
      local attach = require("notmuch.attach.parts")
      local malicious_id = [["msg';touch${IFS}/tmp/notmuch-nvim-poc;'"@example.com]]
      local command
      local json = {
        body = {
          { id = 1, ["content-type"] = "text/plain", ["content-length"] = 4 },
        },
      }

      with_system(function(cmd)
        command = cmd
        return {
          wait = function()
            return { code = 0, stdout = vim.json.encode(json), stderr = "" }
          end,
        }
      end, function()
        with_current_message_id(malicious_id, function()
          attach.get_attachments_from_cursor_msg()
        end)
      end)

      H.eq(6, #command)
      H.eq("id:" .. malicious_id, command[6])
      vim.api.nvim_buf_delete(0, { force = true })
    end,
  },
  {
    name = "attach.parts.get_attachments_from_cursor_msg reports process and JSON failures",
    run = function()
      local attach = require("notmuch.attach.parts")
      local start_buf = vim.api.nvim_get_current_buf()
      local start_wins = #vim.api.nvim_list_wins()
      local old_notify = vim.notify
      local notes = {}
      vim.notify = function(msg, level)
        notes[#notes + 1] = { msg = msg, level = level }
      end

      local ok, err = pcall(function()
        with_system(function()
          return {
            wait = function()
              return { code = 1, stdout = "", stderr = "notmuch failed" }
            end,
          }
        end, function()
          with_current_message_id("process-failure", function()
            H.eq(nil, attach.get_attachments_from_cursor_msg())
          end)
        end)

        H.contains(notes[#notes].msg, "notmuch failed")
        H.eq(vim.log.levels.ERROR, notes[#notes].level)
        H.eq(start_buf, vim.api.nvim_get_current_buf())
        H.eq(start_wins, #vim.api.nvim_list_wins())

        with_system(function()
          return {
            wait = function()
              return { code = 0, stdout = "not-json", stderr = "" }
            end,
          }
        end, function()
          with_current_message_id("json-failure", function()
            H.eq(nil, attach.get_attachments_from_cursor_msg())
          end)
        end)

        H.contains(notes[#notes].msg, "Failed to parse")
        H.eq(vim.log.levels.ERROR, notes[#notes].level)
        H.eq(start_buf, vim.api.nvim_get_current_buf())
        H.eq(start_wins, #vim.api.nvim_list_wins())
      end)

      vim.notify = old_notify
      if not ok then
        error(err, 0)
      end
    end,
  },
  {
    name = "attach.parts.get_attachments_from_cursor_msg returns safely without id or duplicate buffer",
    run = function()
      local attach = require("notmuch.attach.parts")
      local start_buf = vim.api.nvim_get_current_buf()

      with_current_message_id(nil, function()
        H.eq(nil, attach.get_attachments_from_cursor_msg())
      end)
      H.eq(start_buf, vim.api.nvim_get_current_buf())

      local existing = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_name(existing, "id:dup")
      local old_notify = vim.notify
      local note
      vim.notify = function(msg, level)
        note = { msg = msg, level = level }
      end
      with_current_message_id("dup", function()
        H.eq(nil, attach.get_attachments_from_cursor_msg())
      end)
      H.contains(note.msg, "already open")
      H.eq(vim.log.levels.WARN, note.level)

      vim.notify = old_notify
      vim.api.nvim_buf_delete(existing, { force = true })
    end,
  },
  {
    name = "attach.parts.save_attachment_part maps cursor lines, sanitizes filenames, and saves selected part",
    run = function()
      local attach = require("notmuch.attach.parts")
      local dir = H.tmpdir()
      local parts = {
        {
          id = 2,
          content_type = "application/pdf",
          filename = "unsafe/name.pdf",
          disposition = "attachment",
          size = 1,
        },
        { id = 3, content_type = "text/plain", filename = "", disposition = "inline", size = 1 },
      }
      local buf = attachment_buf(parts, "id:save-msg")
      local extractions = {}

      with_save_extractor(function(message_id, part, path)
        extractions[#extractions + 1] = { message_id = message_id, part = part, path = path }
        return path, nil
      end, function()
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        H.eq(nil, attach.save_attachment_part(dir, false))
        vim.api.nvim_win_set_cursor(0, { 6, 0 })
        H.eq(nil, attach.save_attachment_part(dir, false))

        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        local saved
        silence_print(function()
          saved = attach.save_attachment_part(dir, false)
        end)
        H.eq(dir .. "/unsafe-name.pdf", saved)
        H.eq("id:save-msg", extractions[#extractions].message_id)
        H.same(parts[1], extractions[#extractions].part)
        H.eq(dir .. "/unsafe-name.pdf", extractions[#extractions].path)

        vim.api.nvim_win_set_cursor(0, { 5, 0 })
        silence_print(function()
          saved = attach.save_attachment_part(dir, false)
        end)
        H.eq(dir .. "/notmuch.txt", saved)
        H.eq("id:save-msg", extractions[#extractions].message_id)
        H.same(parts[2], extractions[#extractions].part)
        H.eq(dir .. "/notmuch.txt", extractions[#extractions].path)
        H.eq(2, #extractions)
      end)

      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.parts.save_attachment_part reports extraction failures",
    run = function()
      local attach = require("notmuch.attach.parts")
      local dir = H.tmpdir()
      local part = {
        id = 2,
        content_type = "text/plain",
        filename = "failed.txt",
        disposition = "attachment",
        size = 1,
      }
      local buf = attachment_buf({ part }, "id:failed-msg")
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      local old_notify = vim.notify
      local note
      vim.notify = function(msg, level)
        note = { msg = msg, level = level }
      end

      with_save_extractor(function()
        return nil, "extraction failed"
      end, function()
        H.eq(nil, attach.save_attachment_part(dir, false))
      end)

      H.contains(note.msg, "extraction failed")
      H.eq(vim.log.levels.ERROR, note.level)

      vim.notify = old_notify
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.parts.save_attachment_part prompt handles directories, cancellations, missing dirs, and overwrites",
    run = function()
      local attach = require("notmuch.attach.parts")
      local dir = H.tmpdir()
      local empty_dir = H.tmpdir()
      local existing = H.write_file(dir .. "/doc.txt", "old")
      local missing_dir = dir .. "/missing"
      local part = {
        id = 7,
        content_type = "text/plain",
        filename = "doc.txt",
        disposition = "attachment",
        size = 1,
      }
      local buf = attachment_buf({ part }, "id:prompt-msg")
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      local old_input, old_confirm, old_notify = vim.fn.input, vim.fn.confirm, vim.notify
      local notes = {}
      vim.notify = function(msg, level)
        notes[#notes + 1] = { msg = msg, level = level }
      end
      local inputs = { "", missing_dir .. "/doc.txt", empty_dir, existing, existing }
      local confirms = { 2, 1 }
      local extractions = {}
      vim.fn.input = function()
        return table.remove(inputs, 1)
      end
      vim.fn.confirm = function()
        return table.remove(confirms, 1)
      end

      with_save_extractor(function(message_id, selected, path)
        extractions[#extractions + 1] = { message_id = message_id, part = selected, path = path }
        return path, nil
      end, function()
        H.eq(nil, attach.save_attachment_part(nil, true))
        H.contains(notes[#notes].msg, "Save cancelled")
        H.eq(nil, attach.save_attachment_part(nil, true))
        H.contains(notes[#notes].msg, "Directory does not exist")
        local saved
        silence_print(function()
          saved = attach.save_attachment_part(nil, true)
        end)
        H.eq(empty_dir .. "/doc.txt", saved)
        H.eq(nil, attach.save_attachment_part(nil, true))
        H.contains(notes[#notes].msg, "Save cancelled")
        silence_print(function()
          saved = attach.save_attachment_part(nil, true)
        end)
        H.eq(existing, saved)
        H.eq(2, #extractions)
      end)

      vim.fn.input, vim.fn.confirm, vim.notify = old_input, old_confirm, old_notify
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.parts.save_attachment_part reports non-writable prompt directories",
    run = function()
      local attach = require("notmuch.attach.parts")
      local dir = H.tmpdir()
      local part = {
        id = 8,
        content_type = "text/plain",
        filename = "blocked.txt",
        disposition = "attachment",
        size = 1,
      }
      local buf = attachment_buf({ part }, "id:blocked-msg")
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      local old_input, old_notify, old_filewritable = vim.fn.input, vim.notify, vim.fn.filewritable
      local note, extracted
      vim.fn.input = function()
        return dir .. "/blocked.txt"
      end
      vim.fn.filewritable = function(path)
        if path == dir then
          return 0
        end
        return old_filewritable(path)
      end
      vim.notify = function(msg, level)
        note = { msg = msg, level = level }
      end

      with_save_extractor(function()
        extracted = true
      end, function()
        H.eq(nil, attach.save_attachment_part(nil, true))
      end)
      H.contains(note.msg, "Directory is not writable")
      H.eq(vim.log.levels.ERROR, note.level)
      H.eq(nil, extracted)

      vim.fn.input, vim.notify, vim.fn.filewritable = old_input, old_notify, old_filewritable
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "attach.parts.open/view delegates selected part to incoming subsystem",
    run = function()
      local attach = require("notmuch.attach.parts")
      local incoming = require("notmuch.attach.incoming")
      local part = {
        id = 9,
        content_type = "text/plain",
        filename = "view.txt",
        disposition = "attachment",
        size = 1,
      }
      local buf = attachment_buf({ part }, "id:handler-msg")
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      local old_open, old_view = incoming.open_part, incoming.view_part
      local opened, viewed
      incoming.open_part = function(selected, message_id)
        opened = { part = selected, message_id = message_id }
        return true
      end
      incoming.view_part = function(selected, message_id)
        viewed = { part = selected, message_id = message_id }
        return { buf = 1, win = 1 }
      end

      local ok, err = pcall(function()
        H.eq(true, attach.open_attachment_part())
        H.same(part, opened.part)
        H.eq("id:handler-msg", opened.message_id)

        H.same({ buf = 1, win = 1 }, attach.view_attachment_part())
        H.same(part, viewed.part)
        H.eq("id:handler-msg", viewed.message_id)
      end)

      incoming.open_part, incoming.view_part = old_open, old_view
      vim.api.nvim_buf_delete(buf, { force = true })
      if not ok then
        error(err, 0)
      end
    end,
  },
}
