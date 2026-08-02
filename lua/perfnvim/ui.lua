-- lua/perfnvim/ui.lua
-- Floating window utilities.
-- Extracted from commands.lua — provides select_list() for interactive
-- item selection and confirm() for destructive action dialogs.

local M = {}

--- Open a floating window with a list of items for the user to select.
--- @param items table List of display strings
--- @param opts table|nil {
---   prompt = string,         -- window title (default: "Select")
---   border = string,         -- border style (default: "single")
---   max_height = number,     -- max rows (default: 12)
---   on_select = function(index, line_text),
---   on_cancel = function(),
--- }
--- @return number buf, number win
function M.select_list(items, opts)
	opts = opts or {}
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.min(#items, opts.max_height or 12)
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = opts.border or "single",
		title = opts.prompt or "Select",
		title_pos = "center",
	}

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, items)

	-- Make buffer non-modifiable for selection mode
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

	local win = vim.api.nvim_open_win(buf, true, win_opts)

	-- Map Enter to select the current line
	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1]
		vim.api.nvim_win_close(win, true)
		if opts.on_select then
			opts.on_select(cursor[1], line)
		end
	end, { buffer = buf, noremap = true, silent = true })

	-- Map q/Escape to cancel
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
		if opts.on_cancel then opts.on_cancel() end
	end, { buffer = buf, noremap = true, silent = true })
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
		if opts.on_cancel then opts.on_cancel() end
	end, { buffer = buf, noremap = true, silent = true })

	return buf, win
end

--- Show a confirmation dialog.
--- @param prompt string The confirmation message
--- @param opts table|nil {
---   on_confirm = function(),
---   on_cancel = function(),
---   confirm_text = string,  -- default: "Yes"
---   cancel_text = string,   -- default: "No"
--- }
function M.confirm(prompt, opts)
	opts = opts or {}
	local items = { prompt, "" }
	table.insert(items, "[" .. (opts.confirm_text or "Yes") .. "]  " .. (opts.cancel_text or "No"))

	M.select_list(items, {
		prompt = "Confirm",
		max_height = 3,
		on_select = function(idx)
			if idx == 3 then
				if opts.on_confirm then opts.on_confirm() end
			else
				if opts.on_cancel then opts.on_cancel() end
			end
		end,
		on_cancel = opts.on_cancel,
	})
end

return M