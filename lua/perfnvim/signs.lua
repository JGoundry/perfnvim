-- lua/perfnvim/signs.lua
-- Gutter sign management with debouncing.
-- Extracted from change_helpers.lua. Signs are placed/cleared by
-- p4 diff output, parsed in pure Lua.

local M = {}

local constants = require("perfnvim.constants")
local state = require("perfnvim.state")

--- Place signs on a buffer.
local function _place_signs(sign_group, sign_name, lines, bufnr)
	for _, line_num in ipairs(lines) do
		vim.fn.sign_place(0, sign_group, sign_name, bufnr, { lnum = line_num })
	end
end

--- Clear and replace signs for one category.
local function _clear_and_place(sign_group, sign_name, lines, bufnr)
	vim.fn.sign_unplace(sign_group, { buffer = bufnr })
	_place_signs(sign_group, sign_name, lines, bufnr)
end

--- Parse p4 diff output and extract added/changed/deleted line numbers.
--- @param diff_lines table Lines from p4 diff
--- @return table { added={...}, changed={...}, deleted={...} }
function M._parse_diff(diff_lines)
	local added = {}
	local changed = {}
	local deleted = {}

	for _, line in ipairs(diff_lines) do
		-- Added: "5a6,10" or "5a6"
		if line:match("^(%d+)a") then
			local start_num, end_num = line:match("%d+a(%d+),(%d+)")
			if start_num and end_num then
				for i = tonumber(start_num), tonumber(end_num) do
					table.insert(added, i)
				end
			else
				local num = line:match("%d+a(%d+)")
				if num then
					table.insert(added, tonumber(num))
				end
			end
		end

		-- Changed: "5,7c8,10" or "5c8"
		if line:match("^%d+[,?%d+]*c%d+") then
			local start_num, end_num = line:match("c(%d+),?(%d*)")
			if start_num then
				start_num = tonumber(start_num)
				if end_num == "" or end_num == nil then
					end_num = start_num
				else
					end_num = tonumber(end_num)
				end
				for i = start_num, end_num do
					table.insert(changed, i)
				end
			end
		end

		-- Deleted: "5,7d8" or "5d8"
		if line:match("^%d+[,?%d+]*d%d+") then
			local start_num = line:match("d(%d+)")
			if start_num then
				table.insert(deleted, tonumber(start_num))
			end
		end
	end

	return { added = added, changed = changed, deleted = deleted }
end

--- Annotate signs on a buffer from parsed diff output.
--- Does NOT call p4 diff — caller must provide the parsed diff result.
--- @param bufnr number
--- @param diff table { added, changed, deleted }
function M.annotate(bufnr, diff)
	_clear_and_place(constants.p4addSignGroupIdentifier, constants.p4addSignName, diff.added, bufnr)
	_clear_and_place(constants.p4changesSignGroupIdentifier, constants.p4changeSignName, diff.changed, bufnr)
	_clear_and_place(constants.p4deletesSignGroupIdentifier, constants.p4deleteSignName, diff.deleted, bufnr)
end

--- Schedule a debounced sign update for the given buffer.
--- Subsequent calls within debounce_ms cancel the previous timer.
--- @param bufnr number
function M.schedule_update(bufnr)
	-- Cancel existing timer
	if state.sign_timers[bufnr] then
		vim.fn.timer_stop(state.sign_timers[bufnr])
		state.sign_timers[bufnr] = nil
	end

	-- Schedule new update
	state.sign_timers[bufnr] = vim.fn.timer_start(200, function()
		state.sign_timers[bufnr] = nil
		M.update(bufnr)
	end)
end

--- Force an immediate sign update (bypasses debounce).
--- @param bufnr number
function M.update(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Cancel pending timer for this buffer
	if state.sign_timers[bufnr] then
		vim.fn.timer_stop(state.sign_timers[bufnr])
		state.sign_timers[bufnr] = nil
	end

	local filepath = vim.fn.expand("%:p")
	local file_dir = vim.fn.fnamemodify(filepath, ":h")
	local file_name = vim.fn.fnamemodify(filepath, ":t")

	if filepath == "" or not file_name or file_name == "" then
		return
	end

	local stdout = {}
	local stderr = {}

	vim.fn.jobstart({ "p4", "diff", file_name }, {
		cwd = file_dir,
		env = { PWD = file_dir },
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					table.insert(stdout, line)
				end
			end
		end,
		on_stderr = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" and not line:find("file%(s%) not opened") then
						table.insert(stderr, line)
					end
				end
			end
		end,
		on_exit = function(_, exit_code, _)
			if exit_code == 0 or exit_code == 1 then
				-- p4 diff exits 1 when there are differences (normal case)
				local diff = M._parse_diff(stdout)
				vim.schedule(function() M.annotate(bufnr, diff) end)
			end
		end,
	})
end

return M