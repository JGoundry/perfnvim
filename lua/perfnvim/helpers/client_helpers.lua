local M = {}

-- Cache the p4 info output so _GetClientRoot/Name/Stream don't
-- each fire a separate blocking io.popen("p4 info") call.
-- Invalidation: call M._InvalidateInfo() when the workspace changes.
local cached_info = nil

function M._InvalidateInfo()
	cached_info = nil
end

function M._GetP4Info()
	if cached_info then
		return cached_info
	end
	-- Execute the 'p4 info' command and capture the output
	local handle = io.popen("p4 info")
	if not handle then
		print("Failed to run p4 command")
		return
	end
	local result = handle:read("*a")
	handle:close()
	cached_info = result
	return result
end

function M._GetClientRoot()
	local result = M._GetP4Info()
	if result then
		local client_root = result:match("Client root:%s*(.-)\n")
		return client_root
	else
		print("Cannot obtain client root from p4 info")
		return
	end
end

function M._GetClientName()
	local result = M._GetP4Info()
	if result then
		local client_name = result:match("Client name:%s*(.-)\n")
		return client_name
	else
		print("Cannot obtain client name from p4 info")
		return
	end
end

function M._GetClientStream()
	local result = M._GetP4Info()
	if result then
		local client_stream = result:match("Client stream:%s*(.-)\n")
		return client_stream
	else
		print("Cannot obtain client stream from p4 info")
		return
	end
end

return M
