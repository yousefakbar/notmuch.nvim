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
    name = "attach.state get/set normalizes, deduplicates, and returns copies",
    run = function()
      with_draft_root(function(dir)
        local state = require("notmuch.attach.state")
        local file = H.write_file(dir .. "/file.txt", "hello")
        local buf = vim.api.nvim_create_buf(false, true)

        H.same({}, state.get(buf))
        H.eq(
          true,
          state.set(buf, { "  " .. file .. "  ", "", file, 42 }, {
            persist = false,
            refresh_scratch = false,
          })
        )

        local expected = { vim.fn.fnamemodify(file, ":p") }
        H.same(expected, state.get(buf))

        local copy = state.get(buf)
        table.insert(copy, "/mutated")
        H.same(expected, state.get(buf), "state.get should return a defensive copy")
      end)
    end,
  },
  {
    name = "attach.state add/remove validate paths and persist sidecar metadata",
    run = function()
      with_draft_root(function(dir)
        local draft = require("notmuch.draft")
        local state = require("notmuch.attach.state")
        local file = H.write_file(dir .. "/attach.txt", "hello")
        local item = draft.create_compose_draft({ "Subject: State", "", "Body" })
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_var(buf, "notmuch_draft_json_path", item.json_path)

        local ok, path, count = state.add(buf, file, { refresh_scratch = false })
        H.eq(true, ok)
        H.eq(vim.fn.fnamemodify(file, ":p"), path)
        H.eq(1, count)

        local metadata = draft.read_metadata(item.json_path)
        H.same({ vim.fn.fnamemodify(file, ":p") }, metadata.attachments)

        local dup_ok, dup_err = state.add(buf, file, { refresh_scratch = false })
        H.eq(false, dup_ok)
        H.contains(dup_err, "Already attached")

        local missing_ok, missing_err =
          state.add(buf, dir .. "/missing.txt", { refresh_scratch = false })
        H.eq(false, missing_ok)
        H.contains(missing_err, "No such file or directory")

        local rm_ok, removed, remaining = state.remove(buf, file, { refresh_scratch = false })
        H.eq(true, rm_ok)
        H.eq(vim.fn.fnamemodify(file, ":p"), removed)
        H.eq(0, remaining)
        H.same({}, draft.read_metadata(item.json_path).attachments)

        local rm_missing_ok, rm_missing_err = state.remove(buf, file, { refresh_scratch = false })
        H.eq(false, rm_missing_ok)
        H.contains(rm_missing_err, "File not in attachments")
      end)
    end,
  },
}
