local setup = require("perfnvim.setup")
local commands = require("perfnvim.commands")
local M = {}

function M.setup(opts)
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
    setup.setup(opts)
end

function M.P4add()
    commands.SelectChangelistInteractively("add")
end

function M.P4edit()
    commands.SelectChangelistInteractively("edit")
end

function M.P4opened()
    commands.GetP4Opened()
end

function M.P4grep()
    commands.GrepP4Opened()
end

function M.P4next()
    commands.GoToNextChange()
end

function M.P4prev()
    commands.GoToPreviousChange()
end

return M
