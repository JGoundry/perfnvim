-- lua/perfnvim/pickers.lua
-- Telescope pickers for Perforce.
-- Extracted from commands.lua — opened files and grep-across-opened.

local M = {}

local client_helpers = require("perfnvim.helpers.client_helpers")
local file_helpers = require("perfnvim.helpers.file_helpers")

-- Probe for bat/batcat at module load time
local bat_bin = nil
if vim.fn.executable("batcat") == 1 then
	bat_bin = "batcat"
elseif vim.fn.executable("bat") == 1 then
	bat_bin = "bat"
end

--- Telescope picker: list all files opened in Perforce.
--- Displays files relative to client root. Preview uses bat if available.
function M.opened()
	local client_root = client_helpers._GetClientRoot()
	local files = file_helpers._GetP4OpenedPaths()

	if #files == 0 then
		vim.notify("No files opened in Perforce", vim.log.levels.INFO)
		return
	end

	local actions = require("telescope.actions")
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local previewers = require("telescope.previewers")
	local conf = require("telescope.config").values

	-- Transform files to be relative to client_root
	local relative_files = {}
	for _, file in ipairs(files) do
		local relative_path = file:gsub("^" .. client_root .. "/", "")
		table.insert(relative_files, { full_path = file, relative_path = relative_path })
	end

	pickers
		.new({}, {
			prompt_title = "P4 Opened Files",
			finder = finders.new_table({
				results = relative_files,
				entry_maker = function(entry)
					return {
						value = entry.full_path,
						display = entry.relative_path,
						ordinal = entry.relative_path,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_termopen_previewer({
				get_command = function(entry)
					if bat_bin then
						return { bat_bin, "--style=numbers", "--color=always", "--line-range=:500", entry.value }
					end
					return { "file", entry.value }
				end,
			}),
			attach_mappings = function(_, map)
				map("i", "<CR>", actions.select_default)
				map("n", "<CR>", actions.select_default)
				return true
			end,
		})
		:find()
end

--- Telescope picker: grep across all files opened in Perforce.
--- Uses ripgrep with smart-case matching.
function M.grep()
	local files = file_helpers._GetP4OpenedPaths()

	if #files == 0 then
		vim.notify("No files opened in Perforce to grep", vim.log.levels.INFO)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values

	pickers
		.new({}, {
			prompt_title = "Grep P4 Opened Files",
			finder = finders.new_job(function(prompt)
				if prompt == "" then
					return nil
				end
				local args = {
					"rg",
					"--color=never",
					"--no-heading",
					"--with-filename",
					"--line-number",
					"--column",
					"--smart-case",
					prompt,
				}
				for _, f in ipairs(files) do
					table.insert(args, f)
				end
				return args
			end, function(entry)
				local line = type(entry) == "table" and entry[1] or entry
				local filename, lnum, col, text = line:match("([^:]+):(%d+):(%d+):(.*)")
				return {
					value = line,
					display = string.format("%s:%s:%s:%s", filename, lnum, col, text),
					ordinal = text,
					filename = filename,
					lnum = tonumber(lnum),
					col = tonumber(col),
				}
			end),
			sorter = conf.generic_sorter({}),
			previewer = conf.grep_previewer({}),
		})
		:find()
end

return M