local setup = require("perfnvim.setup")
local commands = require("perfnvim.commands")
local M = {}

function M.setup(opts)
	-- Existing commands
	vim.api.nvim_create_user_command("P4add", function()
		commands.SelectChangelistInteractively("add")
	end, {})
	vim.api.nvim_create_user_command("P4edit", function()
		commands.SelectChangelistInteractively("edit")
	end, {})
	vim.api.nvim_create_user_command("P4opened", function()
		commands.GetP4Opened()
	end, {})
	vim.api.nvim_create_user_command("P4grep", function()
		commands.GrepP4Opened()
	end, {})
	vim.api.nvim_create_user_command("P4next", function()
		commands.GoToNextChange()
	end, {})
	vim.api.nvim_create_user_command("P4prev", function()
		commands.GoToPreviousChange()
	end, {})

	-- Phase 4 lifecycle commands
	vim.api.nvim_create_user_command("P4revert", function() commands.Revert() end, {})
	vim.api.nvim_create_user_command("P4revertunchanged", function() commands.RevertUnchanged() end, {})
	vim.api.nvim_create_user_command("P4delete", function() commands.Delete() end, {})
	vim.api.nvim_create_user_command("P4submit", function() commands.Submit() end, {})
	vim.api.nvim_create_user_command("P4diff", function() commands.Diff() end, {})
	vim.api.nvim_create_user_command("P4describe", function() commands.Describe() end, {})
	vim.api.nvim_create_user_command("P4sync", function() commands.Sync() end, {})
	vim.api.nvim_create_user_command("P4annotate", function() commands.Annotate() end, {})
	vim.api.nvim_create_user_command("P4shelve", function() commands.Shelve() end, {})
	vim.api.nvim_create_user_command("P4unshelve", function() commands.Unshelve() end, {})
	vim.api.nvim_create_user_command("P4login", function() commands.Login() end, {})

	setup.setup(opts)
end

-- Public API functions
function M.P4add() commands.SelectChangelistInteractively("add") end
function M.P4edit() commands.SelectChangelistInteractively("edit") end
function M.P4opened() commands.GetP4Opened() end
function M.P4grep() commands.GrepP4Opened() end
function M.P4next() commands.GoToNextChange() end
function M.P4prev() commands.GoToPreviousChange() end
function M.P4revert() commands.Revert() end
function M.P4revertunchanged() commands.RevertUnchanged() end
function M.P4delete() commands.Delete() end
function M.P4submit() commands.Submit() end
function M.P4diff() commands.Diff() end
function M.P4describe() commands.Describe() end
function M.P4sync() commands.Sync() end
function M.P4annotate() commands.Annotate() end
function M.P4shelve() commands.Shelve() end
function M.P4unshelve() commands.Unshelve() end
function M.P4login() commands.Login() end

return M