local d = {}
local nm = require("notmuch")
local r = require("notmuch.refresh")

local function purge_deleted()
  -- Confirm
  vim.ui.select({ "Yes", "No" }, { prompt = "Purge deleted emails ?" }, function(choice)
    if choice == "Yes" then
      -- remove keymap
      vim.keymap.del("n", "DD", { buffer = true })

      -- search for mails to purge
      vim.system(
        { "notmuch", "search", "--output=files", "--format=text0", "tag:del", "and", "tag:/./" },
        function(obj)
          -- purge deleted mails
          for _, file in ipairs(vim.split(obj.stdout, "\0", { plain = true })) do
            vim.uv.fs_unlink(file)
          end
          -- reindex mails
          vim.system({ "notmuch", "new" }, vim.schedule_wrap(
            r.refresh_search_buffer
          ))
        end
      )
    end
  end)
end

d.purge_del = function()
  nm.search_terms("tag:del and tag:/./")
  -- Set keymap for purgin
  vim.keymap.set("n", "DD", function()
    purge_deleted()
  end, { buffer = true })
end

return d
