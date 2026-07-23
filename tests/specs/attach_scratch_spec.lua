local H = dofile("tests/helpers.lua")

local function with_draft_root(fn)
  local config = require("notmuch.config")
  local old_drafts = vim.deepcopy(config.options.drafts)
  local dir = H.tmpdir()
  config.options.drafts = {
    folder = dir .. "/drafts",
    delete_sent = false,
    show_sent_drafts = false,
    auto_open_attachment_window = false,
  }

  local ok, err = pcall(fn, dir)

  config.options.drafts = old_drafts
  pcall(vim.cmd, "silent! %bwipeout!")
  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "attach.scratch opens linked buffer and syncs scratch edits to state and sidecar",
    run = function()
      with_draft_root(function(dir)
        local draft = require("notmuch.draft")
        local state = require("notmuch.attach.state")
        local scratch = require("notmuch.attach.scratch")
        local file1 = H.write_file(dir .. "/one.txt", "one")
        local file2 = H.write_file(dir .. "/two.txt", "two")
        local item = draft.create_compose_draft({ "Subject: Scratch", "", "Body" })

        local draft_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, draft_buf)
        vim.api.nvim_buf_set_var(draft_buf, "notmuch_draft_json_path", item.json_path)
        H.eq(true, state.set(draft_buf, { file1 }, { persist = false, refresh_scratch = false }))

        local scratch_buf = scratch.open(draft_buf)
        H.ok(vim.api.nvim_buf_is_valid(scratch_buf), "scratch buffer should be valid")
        H.eq("notmuch-attach-draft", vim.bo[scratch_buf].filetype)
        H.eq(scratch_buf, vim.api.nvim_buf_get_var(draft_buf, "notmuch_attachment_scratch_buf"))
        H.eq(draft_buf, vim.api.nvim_buf_get_var(scratch_buf, "notmuch_parent_draft_buf"))
        H.same(
          { vim.fn.fnamemodify(file1, ":p") },
          vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
        )

        vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, { file2, "", file2 })
        H.eq(true, scratch.sync_from_scratch(scratch_buf))
        H.same({ vim.fn.fnamemodify(file2, ":p") }, state.get(draft_buf))
        H.same({ vim.fn.fnamemodify(file2, ":p") }, draft.read_metadata(item.json_path).attachments)
      end)
    end,
  },
  {
    name = "attach.scratch refreshes after state changes and sync_open flushes pending edits",
    run = function()
      with_draft_root(function(dir)
        local draft = require("notmuch.draft")
        local state = require("notmuch.attach.state")
        local scratch = require("notmuch.attach.scratch")
        local file1 = H.write_file(dir .. "/one.txt", "one")
        local file2 = H.write_file(dir .. "/two.txt", "two")
        local item = draft.create_compose_draft({ "Subject: Scratch", "", "Body" })

        local draft_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, draft_buf)
        vim.api.nvim_buf_set_var(draft_buf, "notmuch_draft_json_path", item.json_path)
        H.eq(true, state.set(draft_buf, {}, { persist = false, refresh_scratch = false }))

        local scratch_buf = scratch.open(draft_buf)
        local ok = state.add(draft_buf, file1)
        H.eq(true, ok)
        H.same(
          { vim.fn.fnamemodify(file1, ":p") },
          vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
        )

        vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, { file2 })
        H.eq(true, scratch.sync_open(draft_buf))
        H.same({ vim.fn.fnamemodify(file2, ":p") }, state.get(draft_buf))
        H.same({ vim.fn.fnamemodify(file2, ":p") }, draft.read_metadata(item.json_path).attachments)
      end)
    end,
  },
}
