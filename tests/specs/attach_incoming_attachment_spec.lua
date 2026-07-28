local H = dofile("tests/helpers.lua")

return {
  {
    name = "attach.incoming.attachment.from_part normalizes existing MimePart tables",
    run = function()
      local attachment = require("notmuch.attach.incoming.attachment")
      local part = {
        id = 2,
        content_type = "application/pdf",
        filename = "Report.PDF",
        disposition = "attachment",
        size = 12345,
      }

      local att = attachment.from_part(part, "msg-1", "/cache/report.pdf")

      H.eq("/cache/report.pdf", att.path)
      H.eq(2, att.part.id)
      H.eq("application/pdf", att.part.content_type)
      H.eq("Report.PDF", att.part.filename)
      H.eq("attachment", att.part.disposition)
      H.eq(12345, att.part.size)
      H.eq("pdf", att.part.ext)
      H.eq(part, att.part.raw)
      H.eq("msg-1", att.message.id)
    end,
  },
  {
    name = "attach.incoming.attachment.from_part supports raw notmuch MIME keys",
    run = function()
      local attachment = require("notmuch.attach.incoming.attachment")
      local part = {
        id = 3,
        ["content-type"] = "text/html",
        filename = "body.html",
        ["content-disposition"] = "inline",
        ["content-length"] = 99,
      }

      local att = attachment.from_part(part, "msg-2", "/cache/body.html")

      H.eq("/cache/body.html", att.path)
      H.eq(3, att.part.id)
      H.eq("text/html", att.part.content_type)
      H.eq("body.html", att.part.filename)
      H.eq("inline", att.part.disposition)
      H.eq(99, att.part.size)
      H.eq("html", att.part.ext)
      H.eq(part, att.part.raw)
      H.eq("msg-2", att.message.id)
    end,
  },
  {
    name = "attach.incoming.attachment.from_part applies defaults for sparse parts",
    run = function()
      local attachment = require("notmuch.attach.incoming.attachment")
      local part = { id = 4 }

      local att = attachment.from_part(part, "msg-3")

      H.eq(nil, att.path)
      H.eq(4, att.part.id)
      H.eq("application/octet-stream", att.part.content_type)
      H.eq("", att.part.filename)
      H.eq("inline", att.part.disposition)
      H.eq(0, att.part.size)
      H.eq("", att.part.ext)
      H.eq(part, att.part.raw)
      H.eq("msg-3", att.message.id)
    end,
  },
  {
    name = "attach.incoming.attachment.from_part normalizes id-prefixed message ids",
    run = function()
      local attachment = require("notmuch.attach.incoming.attachment")
      local att =
        attachment.from_part({ id = 5, filename = "note.txt" }, "id:abc123", "/cache/note.txt")

      H.eq("abc123", att.message.id)
      H.eq("txt", att.part.ext)
    end,
  },
  {
    name = "attach.incoming.attachment.from_part rejects invalid inputs",
    run = function()
      local attachment = require("notmuch.attach.incoming.attachment")

      local ok, err = pcall(function()
        attachment.from_part(nil, "msg")
      end)
      H.eq(false, ok)
      H.contains(err, "part must be a table")

      ok, err = pcall(function()
        attachment.from_part({}, nil)
      end)
      H.eq(false, ok)
      H.contains(err, "message_id is required")

      ok, err = pcall(function()
        attachment.from_part({}, "")
      end)
      H.eq(false, ok)
      H.contains(err, "message_id is required")
    end,
  },
}
