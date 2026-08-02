-- lua/perfnvim/executor.lua
-- Central async job runner for all p4 commands.
-- Replaces every io.popen and vim.cmd("!p4 ...") in the plugin.
--
-- Usage:
--   executor.run({"diff", file_path}, {
--     cwd = file_dir,
--     on_stdout = function(lines) ... end,
--     on_stderr = function(lines) ... end,
--     on_exit = function(exit_code, stdout_lines, stderr_lines) ... end,
--     buffer = bufnr,  -- optional, for job lifecycle tracking
--     label = "diff",  -- optional, for debugging
--   })
--
-- Error classification:
--   executor.classify("not under client") → "NOT_IN_CLIENT"

local M = {}

--- Map of p4 error substrings → friendly classification.
--- Order matters: longer/more-specific patterns checked first.
local ERROR_PATTERNS = {
	{ "file(s) not opened on this client", "NOT_OPENED" },
	{ "not under client",                  "NOT_IN_CLIENT" },
	{ "is not under client's root",        "NOT_IN_CLIENT" },
	{ "no such file",                      "NO_SUCH_FILE" },
	{ "password",                          "TICKET_EXPIRED" },
	{ "P4PASSWD",                          "TICKET_EXPIRED" },
	{ "login",                             "TICKET_EXPIRED" },
	{ "connect",                           "CONNECT_FAILED" },
	{ "Client .- unknown",                 "CLIENT_UNKNOWN" },
	{ "File(s) not in client view",        "NOT_IN_CLIENT" },
	{ "file(s) not on client",             "NOT_OPENED" },
}

--- Active job tracking: { [job_id] = { buffer, label, started } }
M.jobs = {}

--- Classify a p4 stderr message into a human-readable error code.
--- @param stderr_text string|table The error text or list of lines
--- @return string Error code: "NOT_IN_CLIENT", "TICKET_EXPIRED", etc. or "UNKNOWN"
function M.classify(stderr_text)
	if not stderr_text or stderr_text == "" then
		return "NONE"
	end
	local text = type(stderr_text) == "table"
		and table.concat(stderr_text, "\n")
		or stderr_text
	local lower = text:lower()
	for _, entry in ipairs(ERROR_PATTERNS) do
		if lower:match(entry[1]:lower()) then
			return entry[2]
		end
	end
	return "UNKNOWN"
end

--- Run a p4 command asynchronously.
--- @param args table List of arguments, e.g. {"diff", file_path}
--- @param opts table|nil {
---   cwd = string,          -- working directory for the job
---   env = table,           -- extra environment variables
---   on_stdout = function(lines),  -- called with list of stdout lines
---   on_stderr = function(lines),  -- called with list of stderr lines
---   on_exit = function(exit_code, stdout_lines, stderr_lines),
---   buffer = number,       -- associated buffer for lifecycle tracking
---   label = string,        -- human-readable label for debugging
---   stdout_buffered = bool, -- default true
---   stderr_buffered = bool, -- default true
--- }
--- @return number|nil job_id, or nil on failure
function M.run(args, opts)
	opts = opts or {}
	local command = { "p4" }
	for _, a in ipairs(args) do
		table.insert(command, a)
	end

	local stdout_lines = {}
	local stderr_lines = {}

	local job_opts = {
		stdout_buffered = opts.stdout_buffered ~= false,
		stderr_buffered = opts.stderr_buffered ~= false,
		on_stdout = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					table.insert(stdout_lines, line)
				end
			end
		end,
		on_stderr = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(stderr_lines, line)
					end
				end
			end
		end,
		on_exit = function(_, exit_code, _)
			M.jobs[_] = nil

			-- Schedule callbacks on the main loop
			vim.schedule(function()
				if opts.on_stdout then
					opts.on_stdout(stdout_lines)
				end
				if opts.on_stderr and #stderr_lines > 0 then
					opts.on_stderr(stderr_lines)
				end
				if opts.on_exit then
					opts.on_exit(exit_code, stdout_lines, stderr_lines)
				end
			end)
		end,
	}

	if opts.cwd then
		job_opts.cwd = opts.cwd
	end
	if opts.env then
		job_opts.env = opts.env
	end

	local job_id = vim.fn.jobstart(command, job_opts)
	if job_id <= 0 then
		vim.schedule(function()
			local msg = "perfnvim: failed to start job: p4 " .. table.concat(args, " ")
			vim.notify(msg, vim.log.levels.ERROR)
			if opts.on_exit then
				opts.on_exit(-1, {}, { msg })
			end
		end)
		return nil
	end

	M.jobs[job_id] = {
		buffer = opts.buffer,
		label = opts.label,
		started = os.time(),
	}

	return job_id
end

--- Run a p4 command synchronously (blocking).
--- ONLY use for startup/detection. Never call during user interaction.
--- @param args table List of arguments
--- @param opts table|nil { cwd = string, env = table }
--- @return table { exit_code, stdout_lines, stderr_lines }
function M.run_sync(args, opts)
	opts = opts or {}
	local command = "p4"
	for _, a in ipairs(args) do
		command = command .. " " .. vim.fn.shellescape(a)
	end
	command = command .. " 2>&1"

	local cwd_cmd = ""
	if opts.cwd then
		cwd_cmd = "cd " .. vim.fn.shellescape(opts.cwd) .. " && "
	end

	local output = vim.fn.system(cwd_cmd .. command)
	local exit_code = vim.v.shell_error

	local lines = {}
	for line in output:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	return {
		exit_code = exit_code,
		stdout = lines,
		stderr = {}, -- combined in 2>&1
		output = output,
	}
end

--- Cancel all jobs associated with a buffer.
--- @param bufnr number
function M.cancel_buffer_jobs(bufnr)
	for job_id, job in pairs(M.jobs) do
		if job.buffer == bufnr then
			pcall(vim.fn.jobstop, job_id)
			M.jobs[job_id] = nil
		end
	end
end

--- Cancel a specific job by ID.
--- @param job_id number
function M.cancel(job_id)
	if M.jobs[job_id] then
		pcall(vim.fn.jobstop, job_id)
		M.jobs[job_id] = nil
	end
end

return M