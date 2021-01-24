local float = {}
local v = vim.api

local function open_floating_window_border(win_width, win_height, row, col)
	local border_buf = v.nvim_create_buf(false, true)
	v.nvim_buf_set_option(border_buf, 'bufhidden', 'wipe')
	local border_opts = {
		style = "minimal",
		relative = "editor",
		width = win_width + 2,
		height = win_height + 2,
		row = row - 1,
		col = col - 1
	}
	local border_lines = { '╭' .. string.rep('─', win_width) .. '╮' }
	local middle_line = '│' .. string.rep(' ', win_width) .. '│'
	for i=1, win_height do
		table.insert(border_lines, middle_line)
	end
	table.insert(border_lines, '╰' .. string.rep('─', win_width) .. '╯')
	v.nvim_buf_set_lines(border_buf, 0, -1, false, border_lines)
	local border_win = v.nvim_open_win(border_buf, true, border_opts)
	v.nvim_win_set_option(border_win, 'winhl', 'Normal:Normal')
	return border_buf
end

-- opens a floating scratch buffer
float.open_floating_window = function()
	local buf = v.nvim_create_buf(false, true)
	v.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
	local max_width  = v.nvim_get_option("columns")
	local max_height = v.nvim_get_option("lines")
	local win_width = math.ceil(max_width * 0.8)
	local win_height = math.ceil(max_height * 0.8 - 4)
	local row = math.ceil((max_height - win_height) / 2 - 1)
	local col = math.ceil((max_width - win_width) / 2)
	local opts = {
		style = "minimal",
		relative = "editor",
		width = win_width,
		height = win_height,
		row = row,
		col = col
	}
	local border_buf = open_floating_window_border(win_width, win_height, row, col)
	win = v.nvim_open_win(buf, true, opts)
	v.nvim_command('au BufWipeout <buffer> exe "silent bwipeout! "'..border_buf)
	v.nvim_win_set_option(win, 'winhl', 'Normal:Normal')
	return {
		win = win,
		buf = buf
	}
end

-- opens a floating terminal
float.open_floating_term = function(cmd)
	float.open_floating_window()
	if cmd == nil then
		v.nvim_command('call termopen("zsh")')
	else
		v.nvim_command('call termopen("'..cmd..'")')
	end
	v.nvim_input("a")
end

return float
