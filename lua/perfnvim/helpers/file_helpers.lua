local client_helpers = require("perfnvim.helpers.client_helpers")
local M = {}

-- Get the opened Perforce file paths
function M._GetP4OpenedPaths()
	local client_root = client_helpers._GetClientRoot()
	if not client_root then
		print("Failed to get client root")
		return {}
	end
	local client_stream = client_helpers._GetClientStream()

	-- Run p4 opened and parse the output in Lua instead of
	-- shelling out to awk|sed, which is fragile across p4 output
	-- formats and breaks when client_stream contains special chars.
	local handle = io.popen("p4 opened -s")
	if not handle then
		print("Failed to run p4 opened command")
		return {}
	end
	local result = handle:read("*a")
	handle:close()

	local files = {}
	for line in result:gmatch("[^\r\n]+") do
		-- p4 opened -s format: "//depot/path/file#rev <rest>"
		-- Extract the first whitespace-delimited field (depot path with rev).
		local depot_path = line:match("^(%S+)")
		if depot_path then
			-- Strip the revision suffix (#N)
			depot_path = depot_path:gsub("#%d+$", "")
			-- Map depot path to local filesystem path.
			-- vim.pesc escapes special pattern characters in the stream prefix.
			if client_stream then
				local local_path = depot_path:gsub("^" .. vim.pesc(client_stream), client_root)
				table.insert(files, local_path)
			else
				-- No stream — this is a classic depot. Just use the
				-- depot path relative to the client root.
				-- p4 where <file> would give us the exact mapping, but
				-- calling that per-file is too slow. Fall back to
				-- client_root concatenation (approximate).
				local relative = depot_path:match("^//[^/]+/(.+)$")
				if relative then
					table.insert(files, client_root .. "/" .. relative)
				else
					table.insert(files, depot_path)
				end
			end
		end
	end
	return files
end

return M
