local H = dofile('tests/helpers.lua')

local function part()
  return {
    id = 2,
    content_type = 'application/pdf',
    filename = 'doc.pdf',
    disposition = 'attachment',
    size = 123,
  }
end

return {
  {
    name = 'attach.incoming.open_part extracts builds attachment and opens it',
    run = function()
      local incoming = require('notmuch.attach.incoming')
      local extractor = require('notmuch.attach.incoming.extractor')
      local opener = require('notmuch.attach.incoming.opener')
      local old_extract, old_open = extractor.extract_to_cache, opener.open
      local opened

      extractor.extract_to_cache = function(message_id, selected, opts)
        H.eq('id:msg1', message_id)
        H.eq(2, selected.id)
        H.eq('/cache', opts.cache_dir)
        return '/cache/msg1/2-doc.pdf', nil
      end
      opener.open = function(att, opts)
        opened = { att = att, opts = opts }
        return true, nil
      end

      local ok, err = pcall(function()
        local success, open_err = incoming.open_part(part(), 'id:msg1', {
          cache_dir = '/cache',
          open = { rules = { disable = { 'system' } } },
        })
        H.eq(true, success)
        H.eq(nil, open_err)
        H.eq('/cache/msg1/2-doc.pdf', opened.att.path)
        H.eq('msg1', opened.att.message.id)
        H.eq('application/pdf', opened.att.part.content_type)
        H.same({ disable = { 'system' } }, opened.opts.rules)
      end)

      extractor.extract_to_cache, opener.open = old_extract, old_open
      if not ok then error(err, 0) end
    end,
  },
  {
    name = 'attach.incoming.view_part extracts views and renders attachment',
    run = function()
      local incoming = require('notmuch.attach.incoming')
      local extractor = require('notmuch.attach.incoming.extractor')
      local viewer = require('notmuch.attach.incoming.viewer')
      local renderer = require('notmuch.attach.incoming.renderer')
      local old_extract, old_view, old_render = extractor.extract_to_cache, viewer.view, renderer.render
      local rendered

      extractor.extract_to_cache = function()
        return '/cache/msg1/2-doc.pdf', nil
      end
      viewer.view = function(att, opts)
        H.eq('/cache/msg1/2-doc.pdf', att.path)
        H.same({ disable = { 'pdf' } }, opts.rules)
        return { content = 'preview', filetype = 'text', title = 'doc.pdf' }, nil
      end
      renderer.render = function(result, att, opts)
        rendered = { result = result, att = att, opts = opts }
        return { buf = 10, win = 20 }
      end

      local ok, err = pcall(function()
        local handles, view_err = incoming.view_part(part(), 'msg1', {
          cache_dir = '/cache',
          view = { rules = { disable = { 'pdf' } }, window = { width = 0.5 } },
        })
        H.same({ buf = 10, win = 20 }, handles)
        H.eq(nil, view_err)
        H.eq('preview', rendered.result.content)
        H.eq('msg1', rendered.att.message.id)
        H.eq(0.5, rendered.opts.window.width)
      end)

      extractor.extract_to_cache, viewer.view, renderer.render = old_extract, old_view, old_render
      if not ok then error(err, 0) end
    end,
  },
  {
    name = 'attach.incoming actions notify and stop on extraction/view failures',
    run = function()
      local incoming = require('notmuch.attach.incoming')
      local extractor = require('notmuch.attach.incoming.extractor')
      local viewer = require('notmuch.attach.incoming.viewer')
      local old_extract, old_view, old_notify = extractor.extract_to_cache, viewer.view, vim.notify
      local notes = {}
      vim.notify = function(msg, level) notes[#notes + 1] = { msg = msg, level = level } end

      extractor.extract_to_cache = function()
        return nil, 'extract failed'
      end

      local ok, err = pcall(function()
        local success, open_err = incoming.open_part(part(), 'msg1', { cache_dir = '/cache' })
        H.eq(false, success)
        H.contains(open_err, 'extract failed')
        H.contains(notes[#notes].msg, 'extract failed')

        extractor.extract_to_cache = function()
          return '/cache/file.pdf', nil
        end
        viewer.view = function()
          return nil, 'view failed'
        end
        local handles, view_err = incoming.view_part(part(), 'msg1', { cache_dir = '/cache' })
        H.eq(nil, handles)
        H.contains(view_err, 'view failed')
        H.contains(notes[#notes].msg, 'view failed')
      end)

      extractor.extract_to_cache, viewer.view, vim.notify = old_extract, old_view, old_notify
      if not ok then error(err, 0) end
    end,
  },
}
