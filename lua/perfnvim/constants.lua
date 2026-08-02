local M = {}

-- Sign names and highlight group identifiers
M.p4addSignName = "P4Add"
M.p4addSignGroupIdentifier = "P4Signs"
M.p4addSignHighlight = "P4AddSign"
M.p4changeSignName = "P4Change"
M.p4changesSignGroupIdentifier = "P4Changes"
M.p4changeSignHighlight = "P4ChangeSign"
M.p4deleteSignName = "P4Delete"
M.p4deletesSignGroupIdentifier = "P4deletes"
M.p4deleteSignHighlight = "P4deleteSign"

-- Configurable defaults — merged with user's setup() opts.
M.defaults = {
	p4config_filename = nil, -- nil = use $P4CONFIG or ".p4config"
	signs = {
		enabled = true,
	},
	ui = {
		changelist_popup = {
			border = "single",
			max_height = 12,
		},
	},
}

return M
