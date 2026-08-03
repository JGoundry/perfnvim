-- lua/perfnvim/helpers/path_helper.lua
-- Filesystem path utilities with symlink resolution.
-- Centralises a single policy: resolve paths before comparing with
-- p4 client root, so symlink workspaces (e.g. ~/ubuild → /data/ubuild)
-- don't break path checks and relative-path display.

local M = {}

--- Resolve a path to its canonical form (follows all symlinks).
--- Returns the input unchanged if it's empty or resolves to empty.
--- @param path string
--- @return string
function M.resolve(path)
	if not path or path == "" then
		return path
	end
	local resolved = vim.fn.resolve(path)
	if resolved == "" then
		return path -- fallback: return original
	end
	return resolved
end

--- Check whether a file path is under a given client root,
--- after resolving symlinks on both sides.
--- @param filepath string
--- @param client_root string
--- @return boolean
function M.is_under_root(filepath, client_root)
	if not filepath or filepath == "" or not client_root or client_root == "" then
		return false
	end
	local rfile = M.resolve(filepath):gsub("/$", "")
	local rroot = M.resolve(client_root):gsub("/$", "")
	return rfile:sub(1, #rroot) == rroot
end

--- Get a file path relative to the client root, resolving symlinks.
--- @param filepath string
--- @param client_root string
--- @return string relative path, or the original filepath if not under root
function M.relative_to_root(filepath, client_root)
	if not filepath or filepath == "" or not client_root or client_root == "" then
		return filepath
	end
	local rfile = M.resolve(filepath):gsub("/$", "")
	local rroot = M.resolve(client_root):gsub("/$", "")
	if rfile:sub(1, #rroot) == rroot then
		-- Strip root prefix + trailing slash
		local rel = rfile:sub(#rroot + 1):gsub("^/", "")
		return rel
	end
	return filepath
end

--- Get the directory of a filepath, resolving symlinks.
--- @param filepath string
--- @return string resolved directory path
function M.dirname(filepath)
	if not filepath or filepath == "" then
		return ""
	end
	return vim.fn.fnamemodify(M.resolve(filepath), ":h")
end

--- Get the filename portion of a filepath.
--- @param filepath string
--- @return string filename (no path)
function M.basename(filepath)
	if not filepath or filepath == "" then
		return ""
	end
	return vim.fn.fnamemodify(filepath, ":t")
end

return M