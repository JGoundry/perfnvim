-- lua/perfnvim/health.lua
-- :checkhealth perfnvim integration.
--
-- Provides 8 diagnostic checks:
--   1. p4 binary in PATH
--   2. P4CONFIG environment variable
--   3. P4CONFIG file found in hierarchy
--   4. P4PORT detected
--   5. P4USER detected
--   6. P4CLIENT detected
--   7. p4 info server connectivity
--   8. Current file in workspace

local M = {}

local config = require("perfnvim.config")

--- Format a successful check line.
local function ok(msg)
	vim.health.ok(msg)
end

--- Format a warning check line.
local function warn(msg)
	vim.health.warn(msg)
end

--- Format an error check line.
local function err(msg)
	vim.health.error(msg)
end

--- Format an info line.
local function info(msg)
	vim.health.info(msg)
end

function M.check()
	vim.health.start("PerfNvim")

	-- 1. p4 binary in PATH
	local p4_exec = vim.fn.executable("p4")
	if p4_exec == 1 then
		local version = vim.fn.systemlist("p4 -V")[1] or "p4"
		ok("p4 CLI found: " .. version)
	else
		err("p4 not found in PATH — install Perforce Helix Core CLI")
		return -- can't continue without p4
	end

	-- 2. P4CONFIG env var
	local p4config_env = vim.fn.getenv("P4CONFIG")
	if p4config_env and vim.fn.empty(p4config_env) == 0 then
		ok("P4CONFIG set: " .. p4config_env)
	else
		info("P4CONFIG not set — defaulting to `.p4config`")
		info("Set with: `p4 set P4CONFIG=.p4config`")
	end

	-- 3. P4CONFIG file found
	local cwd = vim.fn.getcwd()
	local filename = config._get_config_filename()
	local files = config._find_config_files(cwd, filename)
	if #files > 0 then
		local paths = {}
		for _, f in ipairs(files) do
			table.insert(paths, f.path)
		end
		ok("P4CONFIG file(s) found:\n  " .. table.concat(paths, "\n  "))
	else
		warn("No `" .. filename .. "` found in directory hierarchy from " .. cwd)
		warn("Without a P4CONFIG file, P4PORT/P4USER/P4CLIENT must come from environment.")
	end

	-- 4–6. Detect merged config
	local detected = config.get(cwd)

	if detected.P4PORT then
		ok("P4PORT detected: " .. detected.P4PORT)
	else
		err("P4PORT not set — cannot reach Perforce server")
	end

	if detected.P4USER then
		ok("P4USER detected: " .. detected.P4USER)
	else
		err("P4USER not set")
	end

	if detected.P4CLIENT then
		ok("P4CLIENT detected: " .. detected.P4CLIENT)
	else
		warn("P4CLIENT not set — using server default")
	end

	-- 7. p4 info server connectivity
	local validation = config.validate()
	if validation.ok then
		local i = validation.info
		local parts = {}
		if i.client then table.insert(parts, "client=" .. i.client) end
		if i.port then table.insert(parts, "port=" .. i.port) end
		if i.root then table.insert(parts, "root=" .. i.root) end
		ok("Connected to P4 server (" .. table.concat(parts, ", ") .. ")")
	else
		for _, e_msg in ipairs(validation.errors) do
			err(e_msg)
		end
	end

	-- 8. Current file in workspace
	local bufnr = vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath ~= "" and validation.info.root then
		-- Normalize paths for comparison
		local normalized_file = vim.fn.fnamemodify(filepath, ":p"):gsub("/$", "")
		local normalized_root = validation.info.root:gsub("/$", "")
		if normalized_file:sub(1, #normalized_root) == normalized_root then
			ok("Current file is under P4 client root")
		else
			warn("Current file is outside the P4 client root — operations disabled")
			warn("  File: " .. normalized_file)
			warn("  Root: " .. normalized_root)
		end
	elseif filepath == "" then
		info("No file in current buffer — open a file to check workspace membership")
	end

	-- Summary
	local has_errors = false
	if not validation.ok then has_errors = true end
	if has_errors then
		err("")
		err("Resolution steps:")
		err("  • If ticket expired: run `p4 login` in your terminal")
		err("  • If server unreachable: check VPN/network and P4PORT value")
		err("  • If client unknown: verify P4CLIENT matches your workspace")
		err("  • If outside workspace: cd into your p4 client root")
	else
		ok("PerfNvim is ready — all checks passed.")
	end

	return not has_errors
end

return M