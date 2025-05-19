local d = {}
local v = vim.api
local nm = require("notmuch")
local r = require("notmuch.refresh")

local confirm_purge = function()
	-- remove keymap
	vim.keymap.del("n", "DD", { buffer = true })
	-- Confirm
	local choice = v.nvim_call_function("confirm", {
		"Purge deleted emails?",
		"&Yes\n&No",
		2, -- Default to no
	})

	if choice == 1 then
		v.nvim_command("silent ! notmuch search --output=files --format=text0 tag:del and tag:/./ | xargs -0 rm")
		v.nvim_command("silent ! notmuch new")
		r.refresh_search_buffer()
	end
end

d.purge_del = function()
	nm.search_terms("tag:del and tag:/./")
	-- Set keymap for purgin
	vim.keymap.set("n", "DD", function()
		confirm_purge()
	end, { buffer = true })
end

return d
