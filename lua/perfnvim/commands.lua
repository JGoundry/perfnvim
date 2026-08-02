local M = {}
local client_helpers = require("perfnvim.helpers.client_helpers")
local file_helpers = require("perfnvim.helpers.file_helpers")
local helpers = require("perfnvim.helpers.other_helpers")
local constants = require("perfnvim.constants")

-- Probe for an available bat binary at module load time.
-- batcat (Debian/Ubuntu) takes priority; bat is a fallback.
-- Returns nil if neither is found — the telescope picker falls back
-- to its built-in previewer.
local bat_bin = nil
if vim.fn.executable("batcat") == 1 then
    bat_bin = "batcat"
elseif vim.fn.executable("bat") == 1 then
    bat_bin = "bat"
end

-- Function to list changelists and allow selection
function M.SelectChangelistInteractively(action)
    -- Get all the different changelist numbers in current client
    -- Alternative commands (1 preferred):
    -- 1 : p4 changelists -s pending -c <clientname> | cut -d' ' -f2
    -- 2 : p4 opened -s | cut -d' ' -f5 | uniq
    local handle = io.popen("p4 changelists -s pending -c " .. client_helpers._GetClientName() .. " | cut -d' ' -f2")
    if not handle then
        print("Failed to run p4 changelists command")
        return
    end
    local result = handle:read("*a")
    handle:close()

    -- Get description for all the changelist numbers
    local changelists = {}
    for changelist in result:gmatch("%d+") do
        -- Fetch the description for each changelist
        local desc_handle = io.popen(string.format("p4 -Ztag -F %%desc%% describe -s %s", changelist))
        if desc_handle then
            local description = desc_handle:read("*a"):gsub("\n", " ")
            desc_handle:close()
            table.insert(changelists, string.format("- Change %s: %s", changelist, description))
        end
    end

    -- Also allow to create a new changelist or send it to the default one
    table.insert(changelists, string.format("Default"))
    table.insert(changelists, string.format("New..."))

    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then
        print("Cannot add/edit file to a changelist: no file associated with the current buffer.")
        return
    end

    -- Create a new buffer and window for displaying changelists
    local newbuf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(newbuf, 0, -1, false, changelists)

    -- Window to choose changelist
    local width = math.floor(vim.o.columns * 0.8) -- 80% of screen width
    local height = 3 * #changelists
    local opts = {
        relative = "editor",
        width = width,
        height = math.min(height, 10),
        col = math.floor((vim.o.columns - width) / 2), -- Center horizontally
        row = math.floor((vim.o.lines - height) / 2), -- Center vertically
        style = "minimal",
        border = "single",
    }

    local win = vim.api.nvim_open_win(newbuf, true, opts)

    -- Map <Enter> to select a changelist
    vim.api.nvim_buf_set_keymap(
        newbuf,
        "n",
        "<CR>",
        ":lua select_changelist_entry()<CR>",
        { noremap = true, silent = true }
    )

    -- Function to handle selection
    _G.select_changelist_entry = function()
        local line = vim.api.nvim_get_current_line()
        local changelist = line:match("Change (%d+)")
        if changelist then
            local cmd = string.format("p4 " .. action .. " -c %s %s", changelist, filepath)
            vim.cmd("!" .. cmd)
            vim.api.nvim_win_close(win, true)
        elseif line:match("Default") then
            local cmd = string.format("p4 " .. action .. " %s", filepath)
            vim.cmd("!" .. cmd)
            vim.api.nvim_win_close(win, true)
        elseif line:match("New...") then
            local placeholder = {
                "Write new changelist description.",
                "Enter insert mode to start writing.",
                "Press enter in normal mode when done.",
            }
            vim.api.nvim_buf_set_lines(newbuf, 0, -1, false, placeholder)

            -- Set buffer option to track if user has started typing
            vim.api.nvim_buf_set_var(newbuf, "first_keystroke", true)
            vim.api.nvim_create_autocmd("InsertEnter", {
                buffer = newbuf,
                callback = function()
                    if vim.api.nvim_buf_get_var(newbuf, "first_keystroke") then
                        vim.api.nvim_buf_set_lines(newbuf, 0, -1, false, { "" })
                        vim.api.nvim_buf_set_var(newbuf, "first_keystroke", false)
                    end
                end,
                once = true,
            })
            -- Map <Enter> to create a new changelist with the entered description
            vim.api.nvim_buf_set_keymap(
                newbuf,
                "n",
                "<CR>",
                ":lua create_new_changelist()<CR>",
                { noremap = true, silent = true }
            )
        else
            print("Error: you did not select a valid line.")
        end
    end

    -- Function to create a new changelist
    _G.create_new_changelist = function()
        -- Get the description entered by the user
        local description = table.concat(vim.api.nvim_buf_get_lines(newbuf, 0, -1, false), "\n")

        if description and description ~= "" then
            -- Create a temporary file to hold the changelist form
            local tmpfile = os.tmpname()

            local p4ChangeHandle = io.popen("p4 change -o")
            if not p4ChangeHandle then
                print("Failed to run p4 change -o command")
                return
            end
            local changelist_form = p4ChangeHandle:read("*a")
            p4ChangeHandle:close()

            -- Modify the changelist form with the desired description
            changelist_form = changelist_form:gsub("(<enter description here.-)\n", description .. "\n")

            -- Write the modified form to the temporary file
            local file = io.open(tmpfile, "w")
            if not file then
                print("Error creating new changelist")
                return
            end
            file:write(changelist_form)
            file:close()

            -- Submit the changelist using the modified form
            local submit_handle = io.popen("p4 change -i < " .. tmpfile)
            if not submit_handle then
                print("Error executing p4 change -i")
                return
            end
            local p4ChangeIResult = submit_handle:read("*a")
            submit_handle:close()

            -- Clean up the temporary file
            os.remove(tmpfile)

            -- Close the window
            vim.api.nvim_win_close(win, true)

            -- Add/edit the file to the created changelist
            local changelist = p4ChangeIResult:match("Change (%d+) created.")
            if changelist then
                local cmd = string.format("p4 " .. action .. " -c %s %s", changelist, filepath)
                vim.cmd("!" .. cmd)
            else
                print("Failed to create changelist")
            end
        else
            print("No description entered. Aborting creation of new changelist.")
        end
    end
end

-- Create a Telescope picker for the p4 opened files
function M.GetP4Opened()
    local p4OpenedHandle = io.popen("p4 opened")
    if not p4OpenedHandle then
        print("Failed to run p4 opened command")
        return
    end
    local p4opened_output = p4OpenedHandle:read("*a")
    local noclient_output = "File(s) not in client view."
    p4OpenedHandle:close()
    if p4opened_output == noclient_output then
        print(noclient_output)
        return
    end
    local actions = require("telescope.actions")
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local previewers = require("telescope.previewers")
    local conf = require("telescope.config").values

    local client_root = client_helpers._GetClientRoot()
    local files = file_helpers._GetP4OpenedPaths()
    -- Transform files to be relative to client_root
    local relative_files = {}
    for _, file in ipairs(files) do
        local relative_path = file:gsub("^" .. client_root .. "/", "")
        table.insert(relative_files, { full_path = file, relative_path = relative_path })
    end
    pickers
        .new({}, {
            prompt_title = "P4 Opened Files",
            finder = finders.new_table({
                results = relative_files,
                entry_maker = function(entry)
                    return {
                        value = entry.full_path,
                        display = entry.relative_path,
                        ordinal = entry.relative_path,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = previewers.new_termopen_previewer({
                get_command = function(entry)
                    if bat_bin then
                        return { bat_bin, "--style=numbers", "--color=always", "--line-range=:500", entry.value }
                    end
                    -- No bat available; telescope falls back to built-in previewer.
                    return { "file", entry.value }
                end,
            }),
            attach_mappings = function(_, map)
                map("i", "<CR>", actions.select_default)
                map("n", "<CR>", actions.select_default)
                return true
            end,
        })
        :find()
end

function M.GrepP4Opened()
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local files = file_helpers._GetP4OpenedPaths()
    -- Join all files with spaces to pass them directly to rg
    pickers
        .new({}, {
            prompt_title = "Grep P4 Opened Files",
            finder = finders.new_job(function(prompt)
                if prompt == "" then
                    return nil
                end
                return {
                    "rg",
                    "--color=never",
                    "--no-heading",
                    "--with-filename",
                    "--line-number",
                    "--column",
                    "--smart-case",
                    prompt,
                    unpack(files), -- Pass files directly as arguments
                }
            end, function(entry)
                -- Convert the entry to string if it's a table
                local line = type(entry) == "table" and entry[1] or entry
                local filename, lnum, col, text = line:match("([^:]+):(%d+):(%d+):(.*)")
                return {
                    value = line,
                    display = string.format("%s:%s:%s:%s", filename, lnum, col, text),
                    ordinal = text,
                    filename = filename,
                    lnum = tonumber(lnum),
                    col = tonumber(col),
                }
            end),
            sorter = conf.generic_sorter({}),
            previewer = conf.grep_previewer({}),
        })
        :find()
end

local target_signs = {
    [constants.p4addSignName] = true,
    [constants.p4changeSignName] = true,
    [constants.p4deleteSignName] = true,
}
function M.GoToPreviousChange()
    -- Get all signs placed in the current buffer
    local buf = vim.fn.bufnr()
    local signs = vim.fn.sign_getplaced(buf, { group = "*" })
    -- Get the current cursor line
    local current_line = vim.fn.line(".")
    -- Iterate over the signs to find the next one
    local continuous_counter = 1
    local signs_array = signs[1].signs
    helpers._ReverseArray(signs_array)
    for _, sign in ipairs(signs_array) do
        if sign.lnum < current_line and target_signs[sign.name] then
            if sign.lnum == (current_line - continuous_counter) then
                continuous_counter = continuous_counter + 1
            else
                vim.fn.sign_jump(sign.id, sign.group, buf)
                return
            end
        end
    end
end

function M.GoToNextChange()
    -- Get all signs placed in the current buffer
    local buf = vim.fn.bufnr()
    local signs = vim.fn.sign_getplaced(buf, { group = "*" })
    -- Get the current cursor line
    local current_line = vim.fn.line(".")
    -- Iterate over the signs to find the next one
    local continuous_counter = 1
    for _, sign in ipairs(signs[1].signs) do
        if sign.lnum > current_line and target_signs[sign.name] then
            if sign.lnum == (current_line + continuous_counter) then
                continuous_counter = continuous_counter + 1
            else
                vim.fn.sign_jump(sign.id, sign.group, buf)
                return
            end
        end
    end
end

return M
