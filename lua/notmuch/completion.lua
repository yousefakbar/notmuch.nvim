local C = {}

local search_terms_list = {
  "attachment:",
  "folder:",
  "id:",
  "mimetype:",
  "property:",
  "subject:",
  "thread:",
  "date:",
  "from:",
  "lastmod:",
  "path:",
  "query:",
  "tag:",
  "is:",
  "to:",
  "body:",
  "and ",
  "or ",
  "not ",
}

local function quote_if_needed(s)
  if s:find("[ %[%]]") then
    return '"' .. s .. '"'
  end
  return s
end

local function uniq_sorted(list)
  table.sort(list)
  local res = {}
  local prev
  for _, v in ipairs(list) do
    if v ~= prev then
      res[#res + 1] = v
      prev = v
    end
  end
  return res
end

local function filter(candidates, prefix)
  return vim.tbl_filter(function(val)
    return vim.startswith(val, prefix)
  end, candidates)
end

local notmuch_mailroot = nil

-- returns the notmuch database root, or nil in case of error
---@return string|nil
local function get_mailroot()
  if notmuch_mailroot then
    return notmuch_mailroot
  end

  local nm_get_config = vim.system({ "notmuch", "config", "get", "database.mail_root" }):wait()
  if nm_get_config.code ~= 0 or #nm_get_config.stdout == 0 then
    vim.notify(
      "notmuch.nvim: Failed to get database.mail_root from notmuch config",
      vim.log.levels.ERROR
    )
    return
  end
  notmuch_mailroot = vim.trim(nm_get_config.stdout)
  return notmuch_mailroot
end

function C.comp_search_terms(arglead, _, _)
  local function fetch_completions()
    if vim.startswith(arglead, "tag:") then
      local tags = vim.fn.systemlist({ "notmuch", "search", "--output=tags", "*" })
      return vim.tbl_map(function(t)
        return "tag:" .. t
      end, tags)
    elseif vim.startswith(arglead, "is:") then
      local tags = vim.fn.systemlist({ "notmuch", "search", "--output=tags", "*" })
      return vim.tbl_map(function(t)
        return "is:" .. t
      end, tags)
    elseif vim.startswith(arglead, "mimetype:") then
      local mimetypes = {
        "application/",
        "audio/",
        "chemical/",
        "font/",
        "image/",
        "inode/",
        "message/",
        "model/",
        "multipart/",
        "text/",
        "video/",
      }
      return vim.tbl_map(function(m)
        return "mimetype:" .. m
      end, mimetypes)
    elseif vim.startswith(arglead, "from:") then
      local addrs = vim.fn.systemlist({ "notmuch", "address", "*" })
      return vim.tbl_map(function(a)
        return "from:" .. a
      end, addrs)
    elseif vim.startswith(arglead, "to:") then
      local addrs = vim.fn.systemlist({ "notmuch", "address", "*" })
      return vim.tbl_map(function(a)
        return "to:" .. a
      end, addrs)
    elseif vim.startswith(arglead, "folder:") then
      local mailroot = get_mailroot()
      if not mailroot then
        return {}
      end

      local dirs = vim.fn.systemlist({
        "find",
        mailroot,
        "-type",
        "d",
        "-name",
        "cur",
      })

      local folders = {}
      local pattern = "^" .. vim.pesc(mailroot) .. "/?"

      for _, dir in ipairs(dirs) do
        local parent = vim.fn.fnamemodify(dir, ":h")
        local rel = parent:gsub(pattern, "")
        if rel ~= "" then
          folders[#folders + 1] = "folder:" .. quote_if_needed(rel)
        end
      end

      return uniq_sorted(folders)
    elseif vim.startswith(arglead, "path:") then
      local mailroot = get_mailroot()
      if not mailroot then
        return {}
      end

      local dirs = vim.fn.systemlist({ "find", mailroot, "-type", "d" })

      local paths = {}
      local pattern = "^" .. vim.pesc(mailroot) .. "/?"

      for _, dir in ipairs(dirs) do
        local rel = dir:gsub(pattern, "")
        if rel ~= "" then
          paths[#paths + 1] = "path:" .. quote_if_needed(rel)
        end
      end

      return uniq_sorted(paths)
    end

    -- default: search terms
    return search_terms_list
  end

  return filter(fetch_completions(), arglead)
end

function C.comp_tags(arglead, _, _)
  return filter(vim.fn.systemlist({ "notmuch", "search", "--output=tags", "*" }), arglead)
end

function C.comp_address(arglead, _, _)
  return filter(vim.fn.systemlist({ "notmuch", "address", "*" }), arglead)
end

return C
