-- lua/perfnvim/commands.lua
-- Command dispatch — thin layer that delegates to specialised modules.
-- Kept minimal: each function forwards to executor, pickers, or ui.

local M = {}

local client_helpers = require("perfnvim.helpers.client_helpers")
local constants = require("perfnvim.constants")
local executor = require("perfnvim.executor")
local notify = require("perfnvim.notify")
local pickers = require("perfnvim.pickers")
local helpers = require("perfnvim.helpers.other_helpers")
local path_helper = require("perfnvim.helpers.path_helper")

----------------------------------------------------------------------
-- Changelist selection (add / edit)
----------------------------------------------------------------------

function M.SelectChangelistInteractively(action)
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		notify.warn("No file associated with the current buffer.")
		return
	end

	local client = client_helpers._GetClientName()
	if not client then
		notify.error("Could not determine P4 client. Is p4 configured?")
		return
	end

	-- Async: fetch pending changelists
	executor.run(
		{ "changelists", "-s", "pending", "-c", client },
		{
			label = "changelists",
			on_exit = function(exit_code, stdout, stderr)
				if exit_code ~= 0 then
					notify.error("Failed to list changelists: " .. table.concat(stderr, "\n"),
						executor.classify(stderr))
					return
				end

				-- Parse changelist numbers from output
				-- Format: "Change 42 on 2024/01/01 by user@client *pending* 'description'"
				local changelists = {}
				for _, line in ipairs(stdout) do
					local num = line:match("Change (%d+)")
					if num then
						-- Extract description
						local desc = line:match("%*pending%* '(.-)'$")
							or line:match("pending '(.-)'$")
							or ""
						table.insert(changelists, {
							number = num,
							description = desc,
							display = string.format("Change %s: %s", num, desc),
						})
					end
				end

				table.insert(changelists, { number = "default", description = "Default changelist",
					display = "Default" })
				table.insert(changelists, { number = "new", description = "", display = "New..." })

				-- Show floating picker
				local ui = require("perfnvim.ui")
				local display_items = {}
				for _, cl in ipairs(changelists) do
					table.insert(display_items, cl.display)
				end

				ui.select_list(display_items, {
					prompt = "Select Changelist (" .. action .. ")",
					max_height = 12,
					on_select = function(idx)
						local selected = changelists[idx]
						if not selected then return end

						if selected.number == "default" then
							executor.run({ action, filepath }, {
								label = action,
								on_exit = function(ec, _, serr)
									if ec == 0 then
										notify.info("p4 " .. action .. " " .. filepath .. " → default")
									else
										notify.error(table.concat(serr, "\n"), executor.classify(serr))
									end
								end,
							})
						elseif selected.number == "new" then
							M._create_new_changelist(action, filepath)
						else
							executor.run({ action, "-c", selected.number, filepath }, {
								label = action,
								on_exit = function(ec, _, serr)
									if ec == 0 then
										notify.info("p4 " .. action .. " → Change " .. selected.number)
									else
										notify.error(table.concat(serr, "\n"), executor.classify(serr))
									end
								end,
							})
						end
					end,
				})
			end,
		}
	)
end

--- Open a buffer for the user to enter a new changelist description,
--- then create it and add/edit the file.
function M._create_new_changelist(action, filepath)
	-- Get the changelist form
	local handle = io.popen("p4 change -o")
	if not handle then
		notify.error("Failed to run p4 change -o")
		return
	end
	local changelist_form = handle:read("*a")
	handle:close()

	-- Show the form in a buffer for editing
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(changelist_form, "\n"))
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].modified = false

	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.7)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "single",
		title = "New Changelist",
		title_pos = "center",
	})

	-- Map <leader>w or <C-s> to save/submit the changelist
	local function submit_cl()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local form = table.concat(lines, "\n")

		-- Write to temp file
		local tmpfile = os.tmpname()
		local f = io.open(tmpfile, "w")
		if not f then
			notify.error("Failed to create temporary file for changelist")
			return
		end
		f:write(form)
		f:close()

		-- Submit via p4 change -i
		local h = io.popen("p4 change -i < " .. tmpfile)
		local result = h:read("*a")
		h:close()
		os.remove(tmpfile)

		vim.api.nvim_win_close(win, true)

		local cl_num = result:match("Change (%d+) created")
		if cl_num then
			executor.run({ action, "-c", cl_num, filepath }, {
				label = action,
				on_exit = function(ec, _, serr)
					if ec == 0 then
						notify.info("p4 " .. action .. " " .. filepath .. " → Change " .. cl_num)
					else
						notify.error(table.concat(serr, "\n"), executor.classify(serr))
					end
				end,
			})
		else
			notify.error("Failed to create changelist: " .. result)
		end
	end

	vim.keymap.set("n", "<leader>w", submit_cl, { buffer = buf })
	vim.keymap.set("n", "<CR>", submit_cl, { buffer = buf })
	vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
end

----------------------------------------------------------------------
-- Telescope pickers (delegated)
----------------------------------------------------------------------

function M.GetP4Opened()
	pickers.opened()
end

function M.GrepP4Opened()
	pickers.grep()
end

----------------------------------------------------------------------
-- Sign navigation
----------------------------------------------------------------------

local target_signs = {
	[constants.p4addSignName] = true,
	[constants.p4changeSignName] = true,
	[constants.p4deleteSignName] = true,
}

function M.GoToPreviousChange()
	local buf = vim.fn.bufnr()
	local signs = vim.fn.sign_getplaced(buf, { group = "*" })
	local current_line = vim.fn.line(".")
	local continuous_counter = 1
	local signs_array = signs[1].signs
	helpers._ReverseArray(signs_array)
	for _, sign in ipairs(signs_array) do
		if sign.lnum < current_line and target_signs[sign.name] then
			if sign.lnum == (current_line - continuous_counter) then
				continuous_counter = continuous_counter + 1
			else
				vim.fn.sign_jump(sign.id, sign.group, buf)
				return
			end
		end
	end
end

function M.GoToNextChange()
	local buf = vim.fn.bufnr()
	local signs = vim.fn.sign_getplaced(buf, { group = "*" })
	local current_line = vim.fn.line(".")
	local continuous_counter = 1
	for _, sign in ipairs(signs[1].signs) do
		if sign.lnum > current_line and target_signs[sign.name] then
			if sign.lnum == (current_line + continuous_counter) then
				continuous_counter = continuous_counter + 1
			else
				vim.fn.sign_jump(sign.id, sign.group, buf)
				return
			end
		end
	end
end

----------------------------------------------------------------------
-- Phase 4: Complete p4 lifecycle commands
----------------------------------------------------------------------

--- Revert current buffer. Confirms before reverting.
function M.Revert()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		notify.warn("No file in current buffer")
		return
	end

	local ui = require("perfnvim.ui")
	ui.confirm("Revert " .. path_helper.basename(filepath) .. "?", {
		on_confirm = function()
			executor.run({ "revert", filepath }, {
				label = "revert",
				on_exit = function(ec, _, serr)
					if ec == 0 then
						notify.info("Reverted: " .. filepath)
						vim.cmd("edit!") -- reload buffer
					else
						notify.error(table.concat(serr, "\n"), executor.classify(serr))
					end
				end,
			})
		end,
	})
end

--- Revert all unchanged files in the workspace.
function M.RevertUnchanged()
	local ui = require("perfnvim.ui")
	ui.confirm("Revert all unchanged files in this workspace?", {
		on_confirm = function()
			executor.run({ "revert", "-a" }, {
				label = "revert-unchanged",
				on_exit = function(ec, stdout, serr)
					if ec == 0 then
						local count = 0
						for _, line in ipairs(stdout) do
							if line:match("reverted") then count = count + 1 end
						end
						notify.info("Reverted " .. count .. " unchanged file(s)")
					else
						notify.error(table.concat(serr, "\n"), executor.classify(serr))
					end
				end,
			})
		end,
	})
end

--- Mark current buffer for deletion.
function M.Delete()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		notify.warn("No file in current buffer")
		return
	end

	local ui = require("perfnvim.ui")
	ui.confirm("Mark " .. path_helper.basename(filepath) .. " for deletion?", {
		on_confirm = function()
			executor.run({ "delete", filepath }, {
				label = "delete",
				on_exit = function(ec, _, serr)
					if ec == 0 then
						notify.info("Marked for deletion: " .. filepath)
					else
						notify.error(table.concat(serr, "\n"), executor.classify(serr))
					end
				end,
			})
		end,
	})
end

--- Submit a changelist. Opens a Telescope picker of pending CLs,
--- then shows a diff summary before confirming submit.
function M.Submit()
	local client = client_helpers._GetClientName()
	if not client then
		notify.error("P4 client not detected")
		return
	end

	executor.run({ "changelists", "-s", "pending", "-u", client_helpers._GetClientName() or "" }, {
		label = "submit-list",
		on_exit = function(ec, stdout, serr)
			if ec ~= 0 then
				notify.error(table.concat(serr, "\n"), executor.classify(serr))
				return
			end

			local cl_list = {}
			for _, line in ipairs(stdout) do
				local num = line:match("Change (%d+)")
				if num then
					local desc = line:match("%*pending%* '(.-)'$") or line:match("pending '(.-)'$") or ""
					table.insert(cl_list, { number = num, display = "Change " .. num .. ": " .. desc })
				end
			end

			if #cl_list == 0 then
				notify.info("No pending changelists to submit")
				return
			end

			local items = {}
			for _, cl in ipairs(cl_list) do
				table.insert(items, cl.display)
			end

			local ui = require("perfnvim.ui")
			ui.select_list(items, {
				prompt = "Submit Changelist",
				max_height = 12,
				on_select = function(idx)
					local cl = cl_list[idx]
					if not cl then return end

					ui.confirm("Submit Change " .. cl.number .. "?\n" .. cl.display, {
						on_confirm = function()
							executor.run({ "submit", "-c", cl.number }, {
								label = "submit",
								on_exit = function(sec, sout, serr2)
									if sec == 0 then
										notify.info("Submitted: Change " .. cl.number)
									else
										notify.error(table.concat(serr2, "\n"), executor.classify(serr2))
									end
								end,
							})
						end,
					})
				end,
			})
		end,
	})
end

--- Show diff of current buffer vs have-revision in a split.
function M.Diff()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		notify.warn("No file in current buffer")
		return
	end

	local file_dir = path_helper.dirname(filepath)
	local file_name = path_helper.basename(filepath)

	vim.cmd("vsplit")
	vim.cmd("enew")
	local diff_buf = vim.api.nvim_get_current_buf()

	vim.fn.jobstart({ "p4", "diff", file_name }, {
		cwd = file_dir,
		env = { PWD = file_dir },
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data, _)
			if data then
				vim.schedule(function()
					vim.api.nvim_buf_set_lines(diff_buf, -1, -1, false, data)
				end)
			end
		end,
		on_exit = function()
			vim.schedule(function()
					vim.bo[diff_buf].filetype = "diff"
					vim.bo[diff_buf].modified = false
				end)
		end,
	})
end

--- Describe a changelist (Telescope picker of pending CLs, shows details).
function M.Describe()
	local client = client_helpers._GetClientName()
	if not client then
		notify.error("P4 client not detected")
		return
	end

	executor.run({ "changelists", "-s", "pending", "-u", client_helpers._GetClientName() or "" }, {
		label = "describe-list",
		on_exit = function(ec, stdout, serr)
			if ec ~= 0 then
				notify.error(table.concat(serr, "\n"), executor.classify(serr))
				return
			end

			local cl_list = {}
			for _, line in ipairs(stdout) do
				local num = line:match("Change (%d+)")
				if num then
					local desc = line:match("%*pending%* '(.-)'$") or line:match("pending '(.-)'$") or ""
					table.insert(cl_list, { number = num, display = "Change " .. num .. ": " .. desc })
				end
			end

			if #cl_list == 0 then
				notify.info("No pending changelists")
				return
			end

			local items = {}
			for _, cl in ipairs(cl_list) do
				table.insert(items, cl.display)
			end

			local ui = require("perfnvim.ui")
			ui.select_list(items, {
				prompt = "Describe Changelist",
				max_height = 12,
				on_select = function(idx)
					local cl = cl_list[idx]
					if not cl then return end

					vim.cmd("vsplit")
					vim.cmd("enew")
					local buf = vim.api.nvim_get_current_buf()

					vim.fn.jobstart({ "p4", "describe", "-s", cl.number }, {
						stdout_buffered = true,
						on_stdout = function(_, data, _)
							if data then
								vim.schedule(function()
									vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
								end)
							end
						end,
						on_exit = function()
							vim.schedule(function()
								vim.bo[buf].filetype = "text"
								vim.bo[buf].modified = false
							end)
						end,
					})
				end,
			})
		end,
	})
end

--- Sync current file to head revision.
function M.Sync()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		notify.warn("No file in current buffer")
		return
	end

	executor.run({ "sync", filepath }, {
		label = "sync",
		on_exit = function(ec, stdout, serr)
			if ec == 0 then
				notify.info("Synced: " .. filepath)
				vim.cmd("edit!")
			else
				notify.error(table.concat(serr, "\n"), executor.classify(serr))
			end
		end,
	})
end

--- Annotate (blame) current file. Opens in a vertical split.
function M.Annotate()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		notify.warn("No file in current buffer")
		return
	end

	vim.cmd("vsplit")
	vim.cmd("enew")
	local buf = vim.api.nvim_get_current_buf()

	vim.fn.jobstart({ "p4", "annotate", "-c", filepath }, {
		stdout_buffered = true,
		on_stdout = function(_, data, _)
			if data then
				vim.schedule(function()
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
				end)
			end
		end,
		on_exit = function()
			vim.schedule(function()
				vim.bo[buf].filetype = "text"
				vim.bo[buf].modified = false
			end)
		end,
	})
end

--- Shelve current changelist.
function M.Shelve()
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		notify.warn("No file in current buffer")
		return
	end

	local ui = require("perfnvim.ui")
	ui.confirm("Shelve changes for " .. path_helper.basename(filepath) .. "?", {
		on_confirm = function()
			executor.run({ "shelve", "-f", filepath }, {
				label = "shelve",
				on_exit = function(ec, _, serr)
					if ec == 0 then
						notify.info("Shelved: " .. filepath)
					else
						notify.error(table.concat(serr, "\n"), executor.classify(serr))
					end
				end,
			})
		end,
	})
end

--- Unshelve a changelist.
function M.Unshelve()
	local client = client_helpers._GetClientName()
	if not client then
		notify.error("P4 client not detected")
		return
	end

	-- List shelved changelists
	executor.run({ "changelists", "-s", "shelved", "-u", client_helpers._GetClientName() or "" }, {
		label = "unshelve-list",
		on_exit = function(ec, stdout, serr)
			if ec ~= 0 then
				notify.error(table.concat(serr, "\n"), executor.classify(serr))
				return
			end

			local cl_list = {}
			for _, line in ipairs(stdout) do
				local num = line:match("Change (%d+)")
				if num then
					local desc = line:match("%*pending%* '(.-)'$") or line:match("pending '(.-)'$") or ""
					table.insert(cl_list, { number = num, display = "Change " .. num .. ": " .. desc })
				end
			end

			if #cl_list == 0 then
				notify.info("No shelved changelists found")
				return
			end

			local items = {}
			for _, cl in ipairs(cl_list) do
				table.insert(items, cl.display)
			end

			local ui = require("perfnvim.ui")
			ui.select_list(items, {
				prompt = "Unshelve Changelist",
				max_height = 12,
				on_select = function(idx)
					local cl = cl_list[idx]
					if not cl then return end

					ui.confirm("Unshelve Change " .. cl.number .. "?", {
						on_confirm = function()
							executor.run({ "unshelve", "-s", cl.number }, {
								label = "unshelve",
								on_exit = function(sec, _, serr2)
									if sec == 0 then
										notify.info("Unshelved Change " .. cl.number)
									else
										notify.error(table.concat(serr2, "\n"), executor.classify(serr2))
									end
								end,
							})
						end,
					})
				end,
			})
		end,
	})
end

--- p4 login flow. Prompts for password and authenticates.
function M.Login()
	local filepath = vim.api.nvim_buf_get_name(0)
	local file_dir = filepath ~= "" and path_helper.dirname(filepath) or vim.fn.getcwd()

	vim.ui.input({ prompt = "P4 password: " }, function(password)
		if not password or password == "" then
			notify.info("Login cancelled")
			return
		end

		-- Write password to stdin via echo | p4 login
		vim.fn.jobstart({ "sh", "-c", "echo " .. vim.fn.shellescape(password) .. " | p4 login" }, {
			cwd = file_dir,
			on_exit = function(_, exit_code)
				vim.schedule(function()
					if exit_code == 0 then
						notify.info("P4 login successful")
					else
						notify.error("P4 login failed — check your password and P4PORT")
					end
				end)
			end,
		})
	end)
end

return M