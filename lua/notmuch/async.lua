-- Running asynchronous commands and capturing stdout
--
-- References:
-- * `:help vim.loop`
-- * https://github.com/luvit/luv/blob/master/docs.md
-- * https://teukka.tech/vimloop.html

-- TODO
-- On read callback, set last line to last found line or something like that

local a = {}
local u = require'notmuch.util'
local v = vim.api
local loop = vim.loop

a.results = {}
a.res_count = 0
function a.onread(err, data)
	if err then
		print('ERROR: ', err)
	end
	if data then
		local vals = vim.split(data, "\n")
		for _, d in pairs(vals) do
			if d == "" then goto continue end
			table.insert(a.results, d)
			a.res_count = a.res_count + 1
			::continue::
		end
	end
end

-- @param tid thread id
function a.async_notmuch_show(tid)
	print(tid)
	-- Create pipes/file descriptors for standard out and error. This is
	-- used to capture the output of the async command that runs
	local stdout = loop.new_pipe(false)
	local stderr = loop.new_pipe(false)

	-- `uv.spawn(path, options, on_exit)`
	-- Spawn the process with the command and arguments (and options)
	handle = loop.spawn('notmuch', {
		args = { 'search', 'tag:ucdavis' },
		stdio = { stdout, stderr }
	},
	vim.schedule_wrap(function()
		stdout:read_stop()
		stderr:read_stop()
		stdout:close()
		stderr:close()
		handle:close()
		-- TODO remove this
		vim.bo.filetype = "notmuch-threads"
		v.nvim_buf_set_lines(0, -2, -1, true, a.results)
		--
		print(a.res_count)
	end
	)
	)
	loop.read_start(stdout, a.onread)
	loop.read_start(stderr, a.onread)
	print('trying: ', handle)
end

return a
