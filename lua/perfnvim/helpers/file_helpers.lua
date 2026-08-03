local M = {}

-- Get the opened Perforce file paths as LOCAL filesystem paths.
-- Runs p4 opened to list depot paths, then resolves them via p4 where
-- (the only reliable cross-version depot→local mapping).
function M._GetP4OpenedPaths()
	-- Get all opened depot paths
	local handle = io.popen("p4 opened 2>&1")
	if not handle then
		vim.notify("perfnvim: Failed to run p4 opened", vim.log.levels.ERROR)
		return {}
	end
	local result = handle:read("*a")
	handle:close()

	-- Extract depot paths (strip #rev suffix)
	local depot_paths = {}
	for line in result:gmatch("[^\r\n]+") do
		local depot = line:match("^(%S+)")
		if depot then
			depot = depot:gsub("#%d+$", "")
			table.insert(depot_paths, depot)
		end
	end

	if #depot_paths == 0 then
		return {}
	end

	-- Resolve depot paths → local paths via p4 where.
	-- Write depot paths to a temp file, feed to p4 -x.
	local tmpfile = os.tmpname()
	local f = io.open(tmpfile, "w")
	if not f then
		return depot_paths -- fallback
	end
	f:write(table.concat(depot_paths, "\n"))
	f:close()

	local where_handle = io.popen("p4 -x " .. tmpfile .. " where 2>&1")
	if not where_handle then
		os.remove(tmpfile)
		return depot_paths -- fallback
	end
	local where_output = where_handle:read("*a")
	where_handle:close()
	os.remove(tmpfile)

	-- p4 where output per line: "depot_path client_path local_path"
	-- e.g. "//depot/main/file.py //client/main/file.py /home/user/file.py"
	-- The third whitespace-delimited field is the local path.
	local files = {}
	for line in where_output:gmatch("[^\r\n]+") do
		-- Skip error lines from p4
		if not line:match("^[%s/]*$") and not line:match("not in client") and not line:match("not under") then
			-- Match the third field: skip depot_path, skip client_path, capture local_path
			local local_path = line:match("^%S+%s+%S+%s+(.+)$")
			if local_path then
				-- Strip trailing newlines/spaces
				local_path = local_path:match("^(.-)%s*$")
				table.insert(files, local_path)
			end
		end
	end

	return files
end

return M