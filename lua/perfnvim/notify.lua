-- lua/perfnvim/notify.lua
-- Standardized notification wrapper.
-- Routes through vim.notify (nvim-notify / noice.nvim compatible).

local M = {}

--- Show an informational notification.
function M.info(msg)
	vim.notify(msg, vim.log.levels.INFO, { title = "PerfNvim" })
end

--- Show a warning notification.
function M.warn(msg)
	vim.notify(msg, vim.log.levels.WARN, { title = "PerfNvim" })
end

--- Show an error notification with optional error classification.
--- Automatically provides actionable guidance for known p4 errors.
function M.error(msg, err_code)
	local title = "PerfNvim"
	local full_msg = msg

	if err_code then
		local hints = {
			TICKET_EXPIRED = "Run `p4 login` to renew your ticket.",
			CONNECT_FAILED = "Check P4PORT, VPN, and network connectivity.",
			NOT_IN_CLIENT = "This file is outside your P4 workspace.",
			CLIENT_UNKNOWN = "P4CLIENT is not recognized. Check your workspace name.",
			NOT_OPENED = "This file is not opened for edit.",
			NO_SUCH_FILE = "File not found in the depot.",
		}
		if hints[err_code] then
			full_msg = msg .. "\n" .. hints[err_code]
		end
	end

	vim.notify(full_msg, vim.log.levels.ERROR, { title = title })
end

return M