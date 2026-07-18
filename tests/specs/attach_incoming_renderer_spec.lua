local H = dofile('tests/helpers.lua')

local function attachment()
  return {
    path = '/tmp/doc.md',
    part = {
      id = 1,
      content_type = 'text/markdown',
      filename = 'doc.md',
      ext = 'md',
    },
    message = { id = 'msg1' },
  }
end

return {
  {
    name = 'attach.incoming.renderer.render creates preview buffer and window',
    run = function()
      local renderer = require('notmuch.attach.incoming.renderer')
      local rendered = renderer.render({
        content = 'line one\nline two',
        filetype = 'markdown',
        title = 'Preview Title',
      }, attachment(), {
        window = {
          width = 40,
          height = 10,
          border = 'single',
        },
      })

      H.ok(vim.api.nvim_buf_is_valid(rendered.buf))
      H.ok(vim.api.nvim_win_is_valid(rendered.win))
      H.same({ 'line one', 'line two' }, vim.api.nvim_buf_get_lines(rendered.buf, 0, -1, false))
      H.eq('markdown', vim.api.nvim_get_option_value('filetype', { buf = rendered.buf }))
      H.eq(false, vim.api.nvim_get_option_value('modifiable', { buf = rendered.buf }))

      local cfg = vim.api.nvim_win_get_config(rendered.win)
      H.eq(40, cfg.width)
      H.eq(10, cfg.height)
      H.eq('table', type(cfg.border))

      vim.api.nvim_win_close(rendered.win, true)
    end,
  },
  {
    name = 'attach.incoming.renderer.render supports percentage dimensions and fallback title',
    run = function()
      local renderer = require('notmuch.attach.incoming.renderer')
      local rendered = renderer.render({
        content = 'body',
        filetype = 'text',
      }, attachment(), {
        window = {
          width = 0.5,
          height = 0.5,
          border = 'rounded',
        },
      })

      local cfg = vim.api.nvim_win_get_config(rendered.win)
      H.eq(math.floor(vim.o.columns * 0.5), cfg.width)
      H.eq(math.floor(vim.o.lines * 0.5), cfg.height)
      H.eq('table', type(cfg.border))

      vim.api.nvim_win_close(rendered.win, true)
    end,
  },
  {
    name = 'attach.incoming.renderer.render q mapping closes preview window',
    run = function()
      local renderer = require('notmuch.attach.incoming.renderer')
      local rendered = renderer.render({ content = 'closable', filetype = 'text' }, attachment())

      local map = vim.fn.maparg('q', 'n', false, true)
      H.eq(1, map.buffer)
      H.eq('function', type(map.callback))
      map.callback()
      H.eq(false, vim.api.nvim_win_is_valid(rendered.win))
    end,
  },
  {
    name = 'attach.incoming.renderer.render validates result input',
    run = function()
      local renderer = require('notmuch.attach.incoming.renderer')
      local ok, err = pcall(function()
        renderer.render(nil, attachment())
      end)

      H.eq(false, ok)
      H.contains(err, 'result must be a table')
    end,
  },
}
