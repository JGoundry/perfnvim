local constants = require("perfnvim.constants")

local M = {}

local function _PlaceSigns(signgroupidentifier, signname, lines, file_path)
	for _, line_num in ipairs(lines) do
		vim.fn.sign_place(0, signgroupidentifier, signname, vim.fn.bufnr(file_path), { lnum = line_num })
	end
end

local function _ClearSignsAndPlace(signgroupidentifier, signname, lines, file_path)
	-- Clear existing signs from the buffer
	vim.fn.sign_unplace(signgroupidentifier, { buffer = vim.fn.bufnr(file_path) })
	-- Place new signs
	_PlaceSigns(signgroupidentifier, signname, lines, file_path)
end

function M._AnnotateAddedLines(lines, file_path)
	local added_lines = {}
	for _, line in ipairs(lines) do
		if line:match("^(%d+)a") then
			local start_num, end_num = line:match("%d+a(%d+),(%d+)")
			if start_num and end_num then
				start_num = tonumber(start_num)
				end_num = tonumber(end_num)
				for i = start_num, end_num do
					table.insert(added_lines, i)
				end
			else
				local num = line:match("%d+a(%d+)")
				if num then
					num = tonumber(num)
					table.insert(added_lines, num)
				end
			end
		end
	end
	_ClearSignsAndPlace(constants.p4addSignGroupIdentifier, constants.p4addSignName, added_lines, file_path)
end

function M._AnnotateDeletedLines(lines, file_path)
	local deleted_lines = {}
	for _, line in ipairs(lines) do
		if line:match("^%d+[,?%d+]*d%d+[,?%d+]") then
			local start_num = line:match("d(%d+)")
			if start_num then
				start_num = tonumber(start_num)
				table.insert(deleted_lines, start_num)
			end
		end
	end
	_ClearSignsAndPlace(constants.p4deletesSignGroupIdentifier, constants.p4deleteSignName, deleted_lines, file_path)
end

function M._AnnotateChangedLines(lines, file_path)
	local changed_lines = {}
	for _, line in ipairs(lines) do
		if line:match("^%d+[,?%d+]*c%d+[,?%d+]") then
			local start_num, end_num = line:match("c(%d+),?(%d*)")
			if start_num then
				start_num = tonumber(start_num)
				if end_num == "" or end_num == nil then
					end_num = start_num
				else
					end_num = tonumber(end_num)
				end
				for i = start_num, end_num do
					table.insert(changed_lines, i)
				end
			end
		end
	end
	_ClearSignsAndPlace(constants.p4changesSignGroupIdentifier, constants.p4changeSignName, changed_lines, file_path)
end

function M._AnnotateSigns()
	local file_path = vim.fn.expand("%:p")
	-- Run "p4 diff" from the file's own directory and pass just the file name, rather than an
	-- absolute path. The client root may be reached through a symlink (e.g. an AltRoot), in which
	-- case %:p resolves to the symlink *target* and p4 rejects it with "not under client's root".
	-- Running from the directory lets p4 resolve the path against the client mapping itself.
	--
	-- We must also set $PWD in the job env: jobstart's `cwd` changes the child's physical working
	-- directory, but the child otherwise inherits $PWD from Neovim (wherever nvim was launched). p4
	-- trusts $PWD over the real cwd both to resolve the relative file name and to locate the
	-- P4CONFIG (.perforce) by walking up. A stale $PWD makes p4 pick the wrong client and report
	-- "not under client's root" / "file(s) not opened on this client".
	local file_dir = vim.fn.fnamemodify(file_path, ":h")
	local file_name = vim.fn.fnamemodify(file_path, ":t")
	local diff_output = {}
	local err_output = {}

	local function on_stdout(job_id, data, event)
		if event == "stdout" and data then
			for _, line in ipairs(data) do
				table.insert(diff_output, line)
			end
		end
	end

	local function on_stderr(job_id, data, event)
		if event == "stderr" and data then
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(err_output, line)
				end
			end
		end
	end

	-- Not every stderr line is a real failure. p4 diff writes these to stderr for perfectly normal
	-- files that simply have nothing to annotate; they must be silenced, not reported:
	--   "<file> - file(s) not opened on this client."  -- tracked but not open for edit
	--   "Path '...' is not under client's root ..."     -- file outside the client (non-p4 files)
	--   "<file> - no such file(s)."                     -- not in the depot
	local function _IsBenignStderr(line)
		return line:find("file%(s%) not opened on this client")
			or line:find("is not under client's root")
			or line:find("no such file%(s%)")
			or line:find("file%(s%) not on client")
	end

	local function on_exit(job_id, exit_code, event)
		if event == "exit" then
			local real_errors = {}
			for _, line in ipairs(err_output) do
				if not _IsBenignStderr(line) then
					table.insert(real_errors, line)
				end
			end
			if #real_errors > 0 then
				vim.schedule(function()
					vim.notify(
						"perfnvim: p4 diff failed for " .. file_path .. "\n" .. table.concat(real_errors, "\n"),
						vim.log.levels.WARN
					)
				end)
				return
			end
			-- Benign stderr (or none) means there is nothing to annotate; an empty diff still runs
			-- through the annotate helpers, which clears any stale signs from the buffer.
			local lines = vim.split(table.concat(diff_output, "\n"), "\n")
			M._AnnotateAddedLines(lines, file_path)
			M._AnnotateChangedLines(lines, file_path)
			M._AnnotateDeletedLines(lines, file_path)
		end
	end

	vim.fn.jobstart({ "p4", "diff", file_name }, {
		cwd = file_dir,
		env = { PWD = file_dir },
		on_stdout = on_stdout,
		on_stderr = on_stderr,
		on_exit = on_exit,
		stdout_buffered = true,
		stderr_buffered = true,
	})
end

return M
