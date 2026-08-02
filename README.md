<h1 align="center">PerfNvim</h1>

<p align="center">
  <b>The Perforce plugin for Neovim.</b><br>
  <em>17 commands, gutter signs, changelist management, Telescope — zero deps beyond Telescope.</em>
</p>

<p align="center">
  <a href="https://github.com/JGoundry/perfnvim/stargazers"><img src="https://img.shields.io/github/stars/JGoundry/perfnvim?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/JGoundry/perfnvim/issues"><img src="https://img.shields.io/github/issues/JGoundry/perfnvim?style=flat-square" alt="Issues"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/JGoundry/perfnvim?style=flat-square" alt="License"></a>
  <a href="https://github.com/guillemaru/perfnvim"><img src="https://img.shields.io/badge/forked%20from-guillemaru%2Fperfnvim-blue?style=flat-square" alt="Fork"></a>
</p>

---

> **Note:** This is a fork of [guillemaru/perfnvim](https://github.com/guillemaru/perfnvim),
> under active development. See [docs/architecture.md](docs/architecture.md) for the
> full audit, module layout, and design constraints.

## Features

| Feature | |
|---|---|
| Gutter signs (add `+`, change `~`, delete `_`) | ✅ |
| Jump between changed lines (`P4next` / `P4prev`) | ✅ |
| P4CONFIG auto-detection — walks up from working directory | ✅ |
| `:checkhealth perfnvim` — 8 diagnostic checks with actionable fixes | ✅ |
| `setup()` with configurable defaults (sign colours, debounce, popups) | ✅ |
| Asynchronous — zero blocking `p4` calls (`vim.fn.jobstart`) | ✅ |
| Error classification (ticket expiry, connection, client errors) | ✅ |
| Debounced sign annotation (200ms after save, no flicker) | ✅ |
| Buffer lifecycle cleanup (cancel jobs/timers on `BufDelete`) | ✅ |
| Cross-platform bat/batcat previewer probe | ✅ |
| Symlink / AltRoot-aware (`p4 diff` from file directory) | ✅ |

**Commands:**

| Command | Key | |
|---|---|---|
| `P4add` | `<leader>pa` | `p4 add` → changelist picker |
| `P4edit` | `<leader>pe` | `p4 edit` → changelist picker |
| `P4revert` | `<leader>pr` | Revert buffer (with confirmation) |
| `P4revertunchanged` | `<leader>pR` | Revert all unchanged files |
| `P4delete` | `<leader>pd` | Mark for deletion (with confirmation) |
| `P4submit` | `<leader>ps` | Pick CL → confirm → submit |
| `P4diff` | `<leader>pD` | Diff vs have-revision (vsplit) |
| `P4describe` | `<leader>pC` | Pick CL → show details |
| `P4sync` | `<leader>pS` | Sync to head, reload |
| `P4annotate` | `<leader>pb` | Blame (vsplit) |
| `P4shelve` | `<leader>ph` | Shelve current file |
| `P4unshelve` | `<leader>pH` | Pick shelved CL → unshelve |
| `P4login` | `<leader>pl` | `p4 login` (password prompt) |
| `P4opened` | `<leader>po` | Telescope: checked-out files |
| `P4grep` | `<leader>pg` | Telescope: grep checked-out files |
| `P4next` | `<leader>pn` | Jump to next changed line |
| `P4prev` | `<leader>pp` | Jump to previous changed line |

Gutter signs appear automatically on `BufReadPost` and `BufWritePost`.

## Installation

Requires Neovim ≥ 0.7, `p4` CLI, and [Telescope](https://github.com/nvim-telescope/telescope.nvim).

```lua
{
    "JGoundry/perfnvim",
    cmd = { "P4add", "P4edit", "P4revert", "P4revertunchanged", "P4delete",
            "P4submit", "P4diff", "P4describe", "P4sync", "P4annotate",
            "P4shelve", "P4unshelve", "P4login", "P4opened", "P4grep",
            "P4next", "P4prev" },
    keys = {
        { "<leader>pa", function() require("perfnvim").P4add() end, desc = "P4 add" },
        { "<leader>pe", function() require("perfnvim").P4edit() end, desc = "P4 edit" },
        { "<leader>pr", function() require("perfnvim").P4revert() end, desc = "P4 revert" },
        { "<leader>pR", function() require("perfnvim").P4revertunchanged() end, desc = "P4 revert unchanged" },
        { "<leader>pd", function() require("perfnvim").P4delete() end, desc = "P4 delete" },
        { "<leader>ps", function() require("perfnvim").P4submit() end, desc = "P4 submit" },
        { "<leader>pD", function() require("perfnvim").P4diff() end, desc = "P4 diff" },
        { "<leader>pC", function() require("perfnvim").P4describe() end, desc = "P4 describe" },
        { "<leader>pS", function() require("perfnvim").P4sync() end, desc = "P4 sync" },
        { "<leader>pb", function() require("perfnvim").P4annotate() end, desc = "P4 annotate" },
        { "<leader>ph", function() require("perfnvim").P4shelve() end, desc = "P4 shelve" },
        { "<leader>pH", function() require("perfnvim").P4unshelve() end, desc = "P4 unshelve" },
        { "<leader>pl", function() require("perfnvim").P4login() end, desc = "P4 login" },
        { "<leader>po", function() require("perfnvim").P4opened() end, desc = "P4 opened" },
        { "<leader>pg", function() require("perfnvim").P4grep() end, desc = "P4 grep" },
        { "<leader>pn", function() require("perfnvim").P4next() end, desc = "Next change" },
        { "<leader>pp", function() require("perfnvim").P4prev() end, desc = "Previous change" },
    },
    config = function()
        require("perfnvim").setup()
    end,
}
```

## Configuration

```lua
require("perfnvim").setup({
    p4config_filename = nil,  -- override $P4CONFIG; nil = ".p4config"
    signs = {
        enabled = true,
    },
    ui = {
        changelist_popup = {
            border = "single",
            max_height = 12,
        },
    },
})
```

## Architecture

| Module | Lines | Concern |
|---|---|---|
| `init.lua` | 63 | Public API + user command registration |
| `setup.lua` | 90 | Config merging + autocmds + sign lifecycle |
| `commands.lua` | 660 | Command dispatch (changelist, lifecycle, navigation) |
| `executor.lua` | 170 | Async job runner (`jobstart`) + error classification |
| `config.lua` | 256 | P4CONFIG walk/parse/merge/validate |
| `health.lua` | 146 | `:checkhealth perfnvim` (8 diagnostics) |
| `signs.lua` | 170 | Gutter signs with debouncing + `p4 diff` parser |
| `pickers.lua` | 135 | Telescope pickers (opened + grep) |
| `ui.lua` | 100 | Floating window utilities |
| `notify.lua` | 50 | Standardised `vim.notify` wrapper |
| `state.lua` | 65 | Centralised state + cache invalidation |
| `constants.lua` | 30 | Sign names + config defaults |
| `helpers/` | 4 files | Client info, file paths, diff parsing, utilities |

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2024 Guillermo Marugan, (c) 2026 Josh Goundry.

## Contributing

Issues and pull requests welcome. Before opening a PR, check
[docs/architecture.md](docs/architecture.md) for the module layout and design
constraints (zero dependencies beyond Telescope, all `p4` calls async, pure Lua).