local M = {}
M.namespace = vim.api.nvim_create_namespace("notmuch.search")

function M.setup()
  local links = {
    Header = "Title",
    Date = "String",
    Count = "Comment",
    Authors = "Identifier",
    AuthorsOther = "Comment",
    Subject = "Normal",
    Tags = "Special",
    Thread = "Comment",
    Hint = "Comment",
    HintKey = "Special",
    Status = "Comment",
    Error = "DiagnosticError",
  }
  local function defaults()
    for name, link in pairs(links) do
      vim.api.nvim_set_hl(0, "NotmuchSearch" .. name, { default = true, link = link })
    end
  end
  defaults()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("NotmuchSearchHighlights", { clear = true }),
    callback = defaults,
  })
end

return M
