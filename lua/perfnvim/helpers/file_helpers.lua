local M = {}

-- Get the opened Perforce file paths as LOCAL filesystem paths.
--
-- The correct approach (used by P4V/P4VS internally):
--   1. p4 opened → list of depot paths
--   2. p4 -x <file> fstat -T clientFile → resolved local paths via workspace
--   3. Parse "... clientFile /local/path" lines
--
-- This is the only reliable cross-version, cross-workspace-type mapping.
-- Streams, classic depots, AltRoots, overlays — all handled by the server.
function M._GetP4OpenedPaths()
	-- Collect depot paths from p4 opened
	local handle = io.popen("p4 opened 2>&1")
	if not handle then
		vim.notify("perfnvim: Failed to run p4 opened", vim.log.levels.ERROR)
		return {}
	end
	local opened_output = handle:read("*a")
	handle:close()

	-- Extract depot paths (must start with //, strip #rev suffix)
	local depot_paths = {}
	for line in opened_output:gmatch("[^\r\n]+") do
		local depot = line:match("^(//%S+)")
		if depot then
			depot = depot:gsub("#%d+$", "") -- strip revision
			table.insert(depot_paths, depot)
		end
	end

	if #depot_paths == 0 then
		return {}
	end

	-- Write depot paths to a temp file for p4 -x
	local tmpfile = vim.fn.tempname()
	local f = io.open(tmpfile, "w")
	if not f then
		return depot_paths -- fallback: return depot paths so picker still works
	end
	f:write(table.concat(depot_paths, "\n"))
	f:close()

	-- Resolve all depot paths to local paths in a single p4 call.
	-- p4 -x <file> fstat -T clientFile:
	--   Reads depot paths from <file>, outputs only clientFile fields.
	--   "... clientFile /home/user/workspace/src/file.py"
	local fstat_handle = io.popen("p4 -x " .. tmpfile .. " fstat -T clientFile 2>&1")
	if not fstat_handle then
		os.remove(tmpfile)
		return depot_paths -- fallback
	end
	local fstat_output = fstat_handle:read("*a")
	fstat_handle:close()
	os.remove(tmpfile)

	-- Parse clientFile paths
	local files = {}
	for line in fstat_output:gmatch("[^\r\n]+") do
		local local_path = line:match("^%.%.%. clientFile (.+)$")
		if local_path then
			table.insert(files, local_path)
		end
	end

	-- If nothing resolved, fall back to depot paths so the picker
	-- at least shows something (user can see what's open even if
	-- the preview might not work).
	if #files == 0 then
		return depot_paths
	end

	return files
end

return M