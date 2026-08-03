-- lua/perfnvim/setup.lua
-- Plugin setup: highlight groups, autocmds, sign definitions, and user config merging.

local constants = require("perfnvim.constants")
local config = require("perfnvim.config")
local signs = require("perfnvim.signs")
local state = require("perfnvim.state")
local path_helper = require("perfnvim.helpers.path_helper")

local M = {}

-- Module-level merged config, accessible by other modules.
M.config = vim.deepcopy(constants.defaults)

--- Deep merge user options into the defaults.
--- Returns the merged table.
local function merge_config(user_opts)
	user_opts = user_opts or {}
	local merged = vim.deepcopy(constants.defaults)
	for k, v in pairs(user_opts) do
		if type(v) == "table" and type(merged[k]) == "table" then
			merged[k] = vim.tbl_deep_extend("force", merged[k], v)
		else
			merged[k] = v
		end
	end
	return merged
end

--- Main setup function. Call once from init.lua or lazy.nvim config.
function M.setup(user_opts)
	M.config = merge_config(user_opts)

	-- Override P4CONFIG filename if user specified one
	if M.config.p4config_filename then
		vim.env.P4CONFIG = M.config.p4config_filename
	end

	-- Sign definitions
	if M.config.signs.enabled then
		vim.api.nvim_set_hl(0, constants.p4addSignHighlight, { fg = "Lime", bg = "NONE" })
		vim.fn.sign_define(constants.p4addSignName, {
			text = "+",
			texthl = constants.p4addSignHighlight,
		})

		vim.api.nvim_set_hl(0, constants.p4changeSignHighlight, { fg = "yellow", bg = "NONE" })
		vim.fn.sign_define(constants.p4changeSignName, {
			text = "~",
			texthl = constants.p4changeSignHighlight,
		})

		vim.api.nvim_set_hl(0, constants.p4deleteSignHighlight, { fg = "red", bg = "NONE" })
		vim.fn.sign_define(constants.p4deleteSignName, {
			text = "_",
			texthl = constants.p4deleteSignHighlight,
		})

		-- Annotate signs on file open and save (debounced on save)
		vim.api.nvim_create_autocmd("BufReadPost", {
			pattern = "*",
			callback = function(args)
				signs.update(args.buf)
			end,
		})
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = "*",
			callback = function(args)
				signs.schedule_update(args.buf)
			end,
		})
	end

	-- Clean up jobs and timers when a buffer is closed
	vim.api.nvim_create_autocmd("BufDelete", {
		pattern = "*",
		callback = function(args)
			local bufnr = args.buf
			-- Cancel pending sign timer
			if state.sign_timers[bufnr] then
				vim.fn.timer_stop(state.sign_timers[bufnr])
				state.sign_timers[bufnr] = nil
			end
			-- Kill any active p4 diff jobs for this buffer
			for job_id, job in pairs(state.jobs) do
				if job.buffer == bufnr then
					pcall(vim.fn.jobstop, job_id)
					state.untrack_job(job_id)
				end
			end
			-- Also check executor's own job tracking table
			local executor = require("perfnvim.executor")
			for job_id, job in pairs(executor.jobs) do
				if job.buffer == bufnr then
					pcall(vim.fn.jobstop, job_id)
					executor.jobs[job_id] = nil
				end
			end
		end,
	})

	-- Invalidate P4CONFIG cache when entering a buffer in a different directory
	vim.api.nvim_create_autocmd("BufEnter", {
		pattern = "*",
		callback = function()
			local buf_path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
			if buf_path ~= "" then
				local dir = path_helper.dirname(buf_path)
				config.detect(dir) -- triggers detection for this workspace
			end
		end,
	})
end

return M