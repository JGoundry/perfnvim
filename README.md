<h1 align="center">PerfNvim</h1>

<p align="center">
  <b>The Perforce plugin for Neovim.</b><br>
  <em>Gutter signs, changelist management, Telescope integration — no dependencies beyond Telescope.</em>
</p>

<p align="center">
  <a href="https://github.com/JGoundry/perfnvim/stargazers"><img src="https://img.shields.io/github/stars/JGoundry/perfnvim?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/JGoundry/perfnvim/issues"><img src="https://img.shields.io/github/issues/JGoundry/perfnvim?style=flat-square" alt="Issues"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/JGoundry/perfnvim?style=flat-square" alt="License"></a>
  <a href="https://github.com/guillemaru/perfnvim"><img src="https://img.shields.io/badge/forked%20from-guillemaru%2Fperfnvim-blue?style=flat-square" alt="Fork"></a>
</p>

---

> **Note:** This is a fork of [guillemaru/perfnvim](https://github.com/guillemaru/perfnvim),
> under active development with the goal of becoming the definitive Perforce plugin for
> Neovim. See [docs/architecture.md](docs/architecture.md) for the full audit and roadmap.

## Features

| Feature | Status |
|---|---|
| Gutter signs for added, changed, and deleted lines | ✅ Done |
| Jump between changed lines (`]h` / `[h` style) | ✅ Done |
| Add / edit current buffer to a changelist | ✅ Done |
| New changelist creation with inline description | ✅ Done |
| Telescope picker: checked-out files | ✅ Done |
| Telescope picker: grep across checked-out files (`rg`) | ✅ Done |
| Cross-platform bat/batcat previewer probe | ✅ Done |
| Symlink / AltRoot-aware (`p4 diff` works from file directory) | ✅ Done |
| `p4 info` result caching (3x fewer blocking calls on picker open) | ✅ Done |
| P4CONFIG auto-detection (walk up, no manual setup) | ✅ Done |
| `:checkhealth perfnvim` diagnostics (8 checks) | ✅ Done |
| Configurable `setup()` with user option merging | ✅ Done |
| Zero blocking calls (all `p4` async) | 🔜 Phase 2 |
| Revert / delete / submit / diff / describe | 🔜 Phase 3–4 |
| Sync / annotate (blame) / shelve–unshelve | 🔜 Phase 3–4 |
| Customizable sign colours and debounce | 🔜 Phase 3 |

## Installation

Requires Neovim ≥ 0.7 and the `p4` CLI in PATH.

### lazy.nvim

```lua
{
    "JGoundry/perfnvim",
    cmd = { "P4add", "P4edit", "P4opened", "P4grep", "P4next", "P4prev" },
    keys = {
        { "<leader>pa", function() require("perfnvim").P4add() end,   desc = "P4 add current buffer" },
        { "<leader>pe", function() require("perfnvim").P4edit() end,  desc = "P4 edit current buffer" },
        { "<leader>po", function() require("perfnvim").P4opened() end, desc = "P4 opened (telescope)" },
        { "<leader>pg", function() require("perfnvim").P4grep() end,  desc = "Grep checked-out files" },
        { "<leader>pn", function() require("perfnvim").P4next() end,  desc = "Next changed line" },
        { "<leader>pp", function() require("perfnvim").P4prev() end,  desc = "Previous changed line" },
    },
    config = function()
        require("perfnvim").setup()
    end,
}
```

### vim-plug

```vim
Plug 'JGoundry/perfnvim'

lua << EOF
require("perfnvim").setup()
EOF
```

## Keybindings

| Key | Action |
|---|---|
| `<leader>pa` | `p4 add` current buffer (opens changelist picker) |
| `<leader>pe` | `p4 edit` current buffer (opens changelist picker) |
| `<leader>po` | Telescope picker of all checked-out files |
| `<leader>pg` | Telescope grep across checked-out files |
| `<leader>pn` | Jump to next changed line |
| `<leader>pp` | Jump to previous changed line |

Gutter signs appear automatically on `BufReadPost` and `BufWritePost` — no keybinding needed.

## Roadmap

| Phase | What | Status |
|---|---|---|
| 0 | Fork, audit, fix critical bugs (batcat, globals, shell pipeline) | ✅ Done |
| 1 | P4CONFIG auto-detection, `:checkhealth`, configurable setup | ✅ Done |
| 2 | Async executor — zero blocking `p4` calls | 🔜 |
| 3 | State management, sign debouncing, p4 info cache | 🔜 |
| 4 | Complete p4 lifecycle: revert, delete, submit, diff, sync, annotate, shelve | 🔜 |
| 5 | UX polish: confirmation dialogs, notifications, error recovery | 🔜 |
| 6 | Documentation, README, which-key verification | 🔜 |

Full details in [docs/architecture.md](docs/architecture.md).

## Demos

<p align="center">
  <img src="./perfnvim1.gif" width="600" alt="Add current buffer to Perforce"/>
  <br><em>Add current buffer to a changelist</em>
</p>

<p align="center">
  <img src="./perfnvim2.gif" width="600" alt="View checked-out files with Telescope"/>
  <br><em>Browse checked-out files with Telescope</em>
</p>

<p align="center">
  <img src="./perfnvim3.gif" width="600" alt="Gutter signs"/>
  <br><em>Gutter signs for added/changed/deleted lines</em>
</p>

## License

MIT — see [LICENSE](LICENSE).

## Contributing

Issues and pull requests welcome. Before opening a PR, check
[docs/architecture.md](docs/architecture.md) for the module layout and design
constraints (zero dependencies beyond Telescope, all p4 calls async, pure Lua).