-- lua/perfnvim/state.lua
-- Centralized, cacheable state for the plugin.
-- All modules read from here instead of calling p4 directly.

local M = {}

--- P4 environment (discovered once, invalidated on BufEnter to new workspace).
M.p4 = {
	port = nil,
	user = nil,
	client = nil,
	root = nil,
	stream = nil,
	version = nil,
}

--- Connection status.
M.connected = nil -- true, false, or nil (unchecked)
M.last_error = nil

--- Active async jobs: { [job_id] = { buffer, label, started } }
M.jobs = {}

--- Sign annotation debounce timers per buffer: { [bufnr] = timer_id }
M.sign_timers = {}

--- Opened files cache (populated by p4 opened, invalidated on add/edit/revert/submit).
M.opened_files = nil
M.opened_files_ts = nil

--- Invalidate the opened files cache.
function M.invalidate_opened()
	M.opened_files = nil
	M.opened_files_ts = nil
end

--- Track an async job.
function M.track_job(job_id, opts)
	M.jobs[job_id] = opts
end

--- Untrack an async job.
function M.untrack_job(job_id)
	M.jobs[job_id] = nil
end

--- Set P4 environment info from parsed p4 info output.
function M.set_info(info)
	M.p4.port = info.port
	M.p4.user = info.user
	M.p4.client = info.client
	M.p4.root = info.root
	M.p4.stream = info.stream
	M.p4.version = info.server_version
	M.connected = true
	M.last_error = nil
end

--- Mark as disconnected with an error message.
function M.set_error(msg)
	M.connected = false
	M.last_error = msg
end

return M