local H = dofile("tests/helpers.lua")

local function fresh_completion()
  package.loaded["notmuch.completion"] = nil
  return require("notmuch.completion")
end

return {
  {
    name = "completion returns and filters default search terms",
    run = function()
      local completion = fresh_completion()
      H.list_contains(completion.comp_search_terms("", "", 0), "tag:")
      H.same({ "tag:" }, completion.comp_search_terms("ta", "", 0))
      H.same({ "and " }, completion.comp_search_terms("and", "", 0))
    end,
  },
  {
    name = "completion completes tags and addresses from notmuch output",
    run = function()
      local old_systemlist = vim.fn.systemlist
      vim.fn.systemlist = function(cmd)
        if cmd[2] == "search" then
          return { "inbox", "unread", "sent" }
        elseif cmd[2] == "address" then
          return { "alice@example.com", "bob@example.com" }
        end
        return {}
      end

      local completion = fresh_completion()
      H.same({ "tag:inbox" }, completion.comp_search_terms("tag:i", "", 0))
      H.same({ "is:unread" }, completion.comp_search_terms("is:u", "", 0))
      H.same({ "from:alice@example.com" }, completion.comp_search_terms("from:a", "", 0))
      H.same({ "to:bob@example.com" }, completion.comp_search_terms("to:b", "", 0))
      H.same({ "bob@example.com" }, completion.comp_address("b", "", 0))
      H.same({ "alice@example.com", "bob@example.com" }, completion.comp_address("", "", 0))
      H.same({ "sent" }, completion.comp_tags("s", "", 0))
      H.same({}, completion.comp_tags("zzz", "", 0))

      vim.fn.systemlist = old_systemlist
    end,
  },
  {
    name = "completion quotes folder and path values and removes duplicates",
    run = function()
      local old_system = vim.system
      local old_systemlist = vim.fn.systemlist
      local mailroot = "/tmp/notmuch mailroot"

      vim.system = function(cmd)
        H.same({ "notmuch", "config", "get", "database.mail_root" }, cmd)
        return {
          wait = function()
            return { code = 0, stdout = mailroot .. "\n" }
          end,
        }
      end

      vim.fn.systemlist = function(cmd)
        if cmd[1] == "find" and cmd[6] == "cur" then
          return {
            mailroot .. "/Inbox/cur",
            mailroot .. "/Projects/With Space/cur",
            mailroot .. "/Projects/With Space/cur",
            mailroot .. "/List[dev]/cur",
          }
        end
        if cmd[1] == "find" then
          return {
            mailroot,
            mailroot .. "/Inbox",
            mailroot .. "/Projects/With Space",
          }
        end
        return {}
      end

      local completion = fresh_completion()
      H.same({ 'folder:"List[dev]"' }, completion.comp_search_terms('folder:"List', "", 0))
      H.same(
        { 'folder:"Projects/With Space"' },
        completion.comp_search_terms('folder:"Projects', "", 0)
      )
      H.same(
        { 'path:"Projects/With Space"' },
        completion.comp_search_terms('path:"Projects', "", 0)
      )

      vim.system = old_system
      vim.fn.systemlist = old_systemlist
    end,
  },
  {
    name = "completion completes top-level MIME types",
    run = function()
      local completion = fresh_completion()
      H.same({ "mimetype:text/" }, completion.comp_search_terms("mimetype:t", "", 0))
      H.list_contains(completion.comp_search_terms("mimetype:", "", 0), "mimetype:application/")
    end,
  },
  {
    name = "completion returns empty folder results when mailroot lookup fails",
    run = function()
      local old_system = vim.system
      local old_notify = vim.notify
      local notified = false

      vim.system = function()
        return {
          wait = function()
            return { code = 1, stdout = "" }
          end,
        }
      end
      vim.notify = function(msg, level)
        notified = msg:find("database.mail_root", 1, true) and level == vim.log.levels.ERROR
      end

      local completion = fresh_completion()
      H.same({}, completion.comp_search_terms("folder:", "", 0))
      H.eq(true, notified)

      vim.system = old_system
      vim.notify = old_notify
    end,
  },
}
