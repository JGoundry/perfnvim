local M = {}

-- Get the opened Perforce file paths as LOCAL filesystem paths.
-- Uses `p4 -Ztag opened` to get clientFile fields directly,
-- avoiding the fragile (and broken) depot→local path mapping.
function M._GetP4OpenedPaths()
	local handle = io.popen("p4 -Ztag opened 2>&1")
	if not handle then
		vim.notify("perfnvim: Failed to run p4 opened", vim.log.levels.ERROR)
		return {}
	end
	local result = handle:read("*a")
	handle:close()

	local files = {}
	for line in result:gmatch("[^\r\n]+") do
		-- p4 -Ztag opened output includes:
		--   ... clientFile /home/user/workspace/src/file.py
		local local_path = line:match("^%.%.%. clientFile (.+)$")
		if local_path then
			table.insert(files, local_path)
		end
	end
	return files
end

return M