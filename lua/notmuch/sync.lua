local s = {}
local v = vim.api

s.sync_maildir = function()
  local sync_cmd = vim.g.NotmuchMaildirSyncCmd .. ' ; notmuch new'
  print('Syncing and reindexing your Maildir...')
  v.nvim_command('!' .. sync_cmd)
end

return s

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
