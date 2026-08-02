-- lua/perfnvim/config.lua
-- P4 environment auto-detection and validation.
--
-- Walks up from a buffer path looking for P4CONFIG file(s),
-- parses them into KEY=VALUE pairs, merges from root→leaf, and
-- provides a validate() function that runs `p4 info` to confirm
-- the environment is usable.
--
-- Caching: detection results are cached per resolved workspace root.
-- Cache is invalidated when the buffer's workspace root changes.

local M = {}

--- Default config filename if $P4CONFIG is not set.
local DEFAULT_FILENAME = ".p4config"

--- Cache: { [workspace_root] = { P4PORT="...", P4USER="...", ... } }
local detect_cache = {}

--- Validate() result cache (short-lived).
local validate_cache = nil
local validate_cache_ts = nil
local VALIDATE_TTL = 30 -- seconds

--- Get the P4CONFIG filename to look for.
--- Uses $P4CONFIG environment variable, falls back to DEFAULT_FILENAME.
function M._get_config_filename()
	local env = vim.fn.getenv("P4CONFIG")
	if env and vim.fn.empty(env) == 0 then
		return env
	end
	return DEFAULT_FILENAME
end

--- Walk up from start_path looking for P4CONFIG files.
--- Returns a list of paths found, ordered from root to leaf (parent first).
--- Each entry: { path = "/full/path/to/.p4config", depth = N }
--- where smaller depth = closer to filesystem root.
function M._find_config_files(start_path, filename)
	local files = {}
	local current = vim.fn.fnamemodify(start_path, ":p"):gsub("/$", "")

	-- Guard against infinite loop and filesystem root.
	local max_depth = 64
	local depth = 0

	while current ~= "" and current ~= "/" and depth < max_depth do
		local candidate = current .. "/" .. filename
		if vim.fn.filereadable(candidate) == 1 then
			table.insert(files, { path = candidate, depth = depth })
		end
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then
			break -- reached filesystem root
		end
		current = parent
		depth = depth + 1
	end

	-- Reverse to get root→leaf order (shallowest first).
	local result = {}
	for i = #files, 1, -1 do
		table.insert(result, files[i])
	end
	return result
end

--- Parse a P4CONFIG file into a key-value table.
--- Skips blank lines and #-comments.
--- Trims whitespace from keys and values.
function M._parse_config_file(filepath)
	local content = {}
	local lines = vim.fn.readfile(filepath)
	for _, line in ipairs(lines) do
		-- Skip blank lines and comments
		line = line:match("^%s*(.-)%s*$") -- trim
		if line ~= "" and not line:match("^#") then
			local key, value = line:match("^([^=]+)=(.*)$")
			if key and value then
				key = key:match("^%s*(.-)%s*$")   -- trim key
				value = value:match("^%s*(.-)%s*$") -- trim value
				if key ~= "" then
					content[key] = value
				end
			end
		end
	end
	return content
end

--- Walk up from start_path, find all P4CONFIG files, parse and merge them
--- parent-first (root values merged, leaf values override).
---
--- Returns { P4PORT="...", P4USER="...", P4CLIENT="...", ... } or {} if
--- no P4CONFIG files are found.
---
--- Cache keyed by start_path directory.
function M.detect(start_path)
	local filename = M._get_config_filename()
	local files = M._find_config_files(start_path, filename)

	if #files == 0 then
		return {}
	end

	-- Merge parent-first: child (closer to workdir) overrides.
	local merged = {}
	for _, entry in ipairs(files) do
		local parsed = M._parse_config_file(entry.path)
		for k, v in pairs(parsed) do
			merged[k] = v -- child overrides parent
		end
	end

	-- Cache by start_path
	detect_cache[start_path] = merged
	return merged
end

--- Run `p4 info` and validate the environment.
--- This is a blocking call — only use during startup or healthcheck.
---
--- Returns { ok = bool, errors = {msg, ...}, info = {...} }
--- where info contains parsed fields from `p4 info` output.
function M.validate()
	-- Return cached result if fresh
	local now = os.time()
	if validate_cache and validate_cache_ts and (now - validate_cache_ts) < VALIDATE_TTL then
		return validate_cache
	end

	local result = {
		ok = true,
		errors = {},
		info = {},
	}

	-- Check p4 binary
	if vim.fn.executable("p4") == 0 then
		result.ok = false
		table.insert(result.errors, "p4 binary not found in PATH")
		validate_cache = result
		validate_cache_ts = now
		return result
	end

	-- Run p4 info
	local handle = io.popen("p4 info 2>&1")
	if not handle then
		result.ok = false
		table.insert(result.errors, "Failed to run p4 info")
		validate_cache = result
		validate_cache_ts = now
		return result
	end

	local output = handle:read("*a")
	local _, exit_type = handle:close()

	-- Parse p4 info output
	for line in output:gmatch("[^\r\n]+") do
		local key, value = line:match("^([^:]+):%s*(.*)$")
		if key and value then
			key = key:gsub("%s+$", "") -- trim trailing whitespace from key
			value = value:gsub("^%s+", ""):gsub("%s+$", "")
			if key == "User name" then result.info.user = value
			elseif key == "Client name" then result.info.client = value
			elseif key == "Client host" then result.info.host = value
			elseif key == "Client root" then result.info.root = value
			elseif key == "Client stream" then result.info.stream = value
			elseif key == "Current directory" then result.info.cwd = value
			elseif key == "Server address" then result.info.port = value
			elseif key == "Server version" then result.info.server_version = value
			end
		end
	end

	-- Classify errors
	local lower = output:lower()
	if exit_type ~= 0 or lower:match("connect to server failed")
		or lower:match("tcp connect")
		or lower:match("name resolution") then
		result.ok = false
		table.insert(result.errors,
			"Cannot connect to P4 server — check P4PORT and network/VPN")
	elseif lower:match("password") or lower:match("p4passwd")
		or lower:match("login") then
		result.ok = false
		table.insert(result.errors,
			"P4 ticket expired or password required — run `p4 login`")
	elseif lower:match("client.*unknown") or lower:match("client.*doesn't exist") then
		result.ok = false
		table.insert(result.errors,
			"P4CLIENT unknown — check your workspace name with `p4 client`")
	elseif lower:match("not under client") then
		result.ok = false
		table.insert(result.errors,
			"Current directory is not under a P4 client root")
	elseif lower:match("no such file") then
		result.ok = false
		table.insert(result.errors, "File not found in depot")
	end

	-- Check if critical fields are missing
	if not result.info.client then
		result.ok = false
		table.insert(result.errors, "P4CLIENT not set — no workspace detected")
	end
	if not result.info.user then
		result.ok = false
		table.insert(result.errors, "P4USER not set")
	end
	if not result.info.port then
		result.ok = false
		table.insert(result.errors, "P4PORT not set — cannot reach server")
	end

	validate_cache = result
	validate_cache_ts = now
	return result
end

--- Get detection for current buffer or a given path.
--- Combines detect() with environment variables as fallback.
function M.get(start_path)
	start_path = start_path or vim.fn.expand("%:p:h")
	local detected = M.detect(start_path)

	-- Fill gaps from environment variables
	local env_map = {
		P4PORT = "port",
		P4USER = "user",
		P4CLIENT = "client",
		P4TICKETS = "tickets",
		P4CHARSET = "charset",
	}
	for env_key, out_key in pairs(env_map) do
		if not detected[env_key] then
			local val = vim.fn.getenv(env_key)
			if val and vim.fn.empty(val) == 0 then
				detected[env_key] = val
			end
		end
	end

	return detected
end

--- Clear all caches (useful when workspace changes).
function M.invalidate()
	detect_cache = {}
	validate_cache = nil
	validate_cache_ts = nil
end

return M