local H = dofile("tests/helpers.lua")

local function with_draft_env(fn)
  local config = require("notmuch.config")
  local old_drafts = vim.deepcopy(config.options.drafts)
  local dir = H.tmpdir()
  config.options.drafts = {
    folder = dir .. "/drafts",
    delete_sent = false,
    show_sent_drafts = false,
  }

  local ok, err = pcall(fn, require("notmuch.draft"), config, dir)

  config.options.drafts = old_drafts
  pcall(vim.cmd, "silent! %bwipeout!")
  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "draft creates, loads, lists, and filters compose drafts",
    run = function()
      with_draft_env(function(draft, config)
        local one =
          draft.create_compose_draft({ "From: a@example.com", "Subject: First", "", "Body" })
        H.ok(one, "expected compose draft")
        H.matches(
          one.eml_path,
          "/compose/compose%-%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ%-%x%x%x%x%x%x%x%x%.eml$"
        )
        H.ok(vim.uv.fs_stat(one.eml_path), "missing eml")
        H.ok(vim.uv.fs_stat(one.json_path), "missing json sidecar")
        H.eq("compose", one.metadata.kind)
        H.same({}, one.metadata.attachments)
        H.eq(vim.NIL, one.metadata.sent_at)

        local loaded = draft.load_compose_draft(one.eml_path)
        H.eq("First", loaded.subject)
        H.eq(one.json_path, loaded.json_path)

        local two = draft.create_compose_draft({ "Subject: Second", "", "Body" })
        draft.mark_sent(two.json_path)
        local unsent = draft.list_compose_drafts()
        H.eq(1, #unsent)
        H.eq(one.eml_path, unsent[1].eml_path)

        config.options.drafts.show_sent_drafts = true
        local all = draft.list_compose_drafts()
        H.eq(2, #all)
      end)
    end,
  },
  {
    name = "draft creates reply groups and lists reply drafts",
    run = function()
      with_draft_env(function(draft, config)
        local message_id = "msg/with/slash"
        local group = draft.ensure_reply_group(message_id)
        H.eq(vim.fs.joinpath(draft.replies_dir(), vim.fn.sha256(message_id)), group)
        local group_meta = draft.read_metadata(draft.reply_group_metadata_path(message_id))
        H.eq(message_id, group_meta.message_id)

        local reply = draft.create_reply_draft(message_id, { "Subject: Re: Test", "", "reply" })
        H.eq("reply", reply.kind)
        H.eq(message_id, reply.metadata.message_id)
        H.eq("Re: Test", reply.subject)

        local sent_reply =
          draft.create_reply_draft(message_id, { "Subject: Sent Reply", "", "sent reply" })
        draft.mark_sent(sent_reply.json_path)

        local replies = draft.list_reply_drafts(message_id)
        H.eq(1, #replies)
        H.eq(reply.eml_path, replies[1].eml_path)
        H.same({}, draft.list_reply_drafts("missing/id") or {})

        H.eq(1, #draft.list_all_reply_drafts())
        H.eq(1, #draft.list_all_drafts())

        config.options.drafts.show_sent_drafts = true
        H.eq(2, #draft.list_reply_drafts(message_id))
        H.eq(2, #draft.list_all_reply_drafts())
        H.eq(2, #draft.list_all_drafts())
      end)
    end,
  },
  {
    name = "draft persists attachments, marks sent, and deletes draft files",
    run = function()
      with_draft_env(function(draft, _, dir)
        local attachment = H.write_file(dir .. "/a.txt", "a\n")
        local item = draft.create_compose_draft({ "Subject: Attach", "", "Body" })

        H.eq(true, draft.save_attachments(item.json_path, { attachment }))
        local metadata = draft.read_metadata(item.json_path)
        H.same({ attachment }, metadata.attachments)

        local buf = vim.api.nvim_create_buf(true, true)
        H.eq(true, draft.save_buffer_attachments(buf, { "ignored" }))
        vim.api.nvim_buf_set_var(buf, "notmuch_draft_json_path", item.json_path)
        H.eq(true, draft.save_buffer_attachments(buf, {}))
        H.same({}, draft.read_metadata(item.json_path).attachments)

        H.eq(true, draft.mark_sent(item.json_path))
        H.ok(draft.read_metadata(item.json_path).sent_at ~= vim.NIL, "expected sent_at")

        local old_notify = vim.notify
        vim.notify = function() end
        local bad_delete = draft.delete_draft(dir .. "/not-eml.txt")
        vim.notify = old_notify
        H.eq(false, bad_delete)
        H.eq(true, draft.delete_draft(item))
        H.ok(not vim.uv.fs_stat(item.eml_path), "eml should be deleted")
        H.ok(not vim.uv.fs_stat(item.json_path), "json should be deleted")
      end)
    end,
  },
}
