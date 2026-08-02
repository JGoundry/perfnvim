# PerfNvim Architecture Audit

> Generated 2026-08-02 from upstream `guillemaru/perfnvim` at tag `upstream-last-sync`
> (commit `80264e6`).

## Overview

PerfNvim is a 664-line Lua plugin that integrates Perforce (`p4`) into Neovim with
gutter signs, changelist management, and Telescope pickers. It has zero dependencies
beyond Telescope — all `p4` calls go through `io.popen` or `vim.fn.jobstart`.

## Module Inventory

```
lua/perfnvim/
├── init.lua                      51 lines — public API + user command registration
├── setup.lua                     32 lines — highlight groups + BufReadPost/BufWritePost autocmd
├── commands.lua                 320 lines — ⚠️ OVERLOADED: p4 execution, floating window UI,
│                                             Telescope pickers, sign navigation
├── constants.lua                 13 lines — sign names + highlight group identifiers
└── helpers/
    ├── change_helpers.lua       160 lines — async `p4 diff` → gutter sign placement (✅ good)
    ├── client_helpers.lua        48 lines — `p4 info` parsers (⚠️ blocking, 3x redundant calls)
    ├── file_helpers.lua          30 lines — `p4 opened` → file path resolution (⚠️ blocking,
    │                                         fragile awk|sed pipeline)
    └── other_helpers.lua         10 lines — `_ReverseArray` utility
```

## Call Graph

```
setup()
  └─ change_helpers._AnnotateSigns()        [async, jobstart]
       ├─ _AnnotateAddedLines()
       ├─ _AnnotateChangedLines()
       └─ _AnnotateDeletedLines()

P4add / P4edit
  └─ commands.SelectChangelistInteractively("add"|"edit")
       ├─ io.popen("p4 changelists ...")     [⚠️ blocking]
       ├─ io.popen("p4 describe ...") ×N     [⚠️ blocking]
       ├─ io.popen("p4 change -o")           [⚠️ blocking, New... only]
       ├─ io.popen("p4 change -i")           [⚠️ blocking, New... only]
       └─ vim.cmd("!p4 ...")                 [⚠️ shell escape]

P4opened
  └─ commands.GetP4Opened()
       ├─ io.popen("p4 opened")              [⚠️ blocking]
       ├─ client_helpers._GetClientRoot()     [⚠️ blocking]
       └─ file_helpers._GetP4OpenedPaths()    [⚠️ blocking, awk|sed]

P4grep
  └─ commands.GrepP4Opened()
       └─ file_helpers._GetP4OpenedPaths()    [⚠️ blocking, awk|sed]

P4next / P4prev
  └─ commands.GoToNextChange() / GoToPreviousChange()   [✅ fast, sign queries only]
```

## Blocking Call Inventory

| Site | Command | Latency | User-Visible Effect |
|---|---|---|---|
| `commands:13` | `p4 changelists -s pending -c <client>` | 200–500ms | Changelist picker freezes editor |
| `commands:25-28` | `p4 describe -s <CL>` per CL | ~100ms × N | Linear degradation with CL count |
| `commands:77,81,163` | `vim.cmd("!" .. cmd)` | 200–500ms | Shell escape — visually disruptive, writes to terminal |
| `commands:176` | `p4 opened` | 300–800ms | Telescope picker blocks on open |
| `file_helpers:15` | `p4 opened -s \| awk \| sed` | 300–800ms | Telescope grep picker blocks on open |
| `client_helpers:5` | `p4 info` | 100–200ms | Every client helper call blocks |
| `commands:125` | `p4 change -o` | 100–200ms | New changelist blocks |
| `commands:146` | `p4 change -i` | 150–300ms | New changelist creation blocks |

**Total worst case** (changelist picker with 5 CLs): ~1,200–2,500ms blocking.

## Global State Pollution

| Site | Global | Impact |
|---|---|---|
| `commands:72` | `_G.select_changelist_entry` | Leaks into global namespace, no cleanup |
| `commands:117` | `_G.create_new_changelist` | Leaks into global namespace, no cleanup |

Both are used as callbacks for `nvim_buf_set_keymap` which only accepts string
references (no closure direct binding). Workaround: use `callback` with
`nvim_buf_set_keymap`'s `callback` option (Neovim 0.7+), or use `nvim_create_autocmd`
with a buffer-local `BufWipeout` cleanup.

## Hardcoded Assumptions

| Site | Issue | Fix |
|---|---|---|
| `commands:218` | `batcat` binary name hardcoded | Probe for `batcat` / `bat` at setup time |
| `file_helpers:15` | `awk '{print $1}' \| sed` pipeline | Parse `p4 opened -s` output in Lua |
| `commands:12` | `cut -d' ' -f2` assumes single-space | Use `p4 -Ztag -F %change%` or parse in Lua |
| `commands:49` | `height = 3 * #changelists` min 10 | Cap at 12 rows, use scrollable list |
| `commands:50` | `row` calculated from `height` before min | Row should use min(height, 12) consistently |
| `client_helpers` | 3x redundant `p4 info` calls | Cache result, single parse |

## Errors Unhandled

| Scenario | Current Behavior |
|---|---|
| `p4` not in PATH | `io.popen` returns nil, prints "Failed to run p4 command" |
| Ticket expired | `p4` errors go to stderr, no user-visible notification |
| Not in a client workspace | "File(s) not in client view" printed, no guidance |
| Network timeout | Hangs on `io.popen` with no timeout |
| Binary file diff | `p4 diff` outputs garbage; change_helpers handles benign stderr |
| File outside client root | Handled in change_helpers (benign stderr filtering) ✅ |

## What Works Well

- **Gutter signs**: Async via `jobstart`, benign stderr filtering, symlink/AltRoot-aware (commit `56005bc`)
- **Next/prev change jump**: Fast, sign-index-based, `continuous_counter` skip logic
- **Telescope grep**: Full `rg` passthrough with column/line parsing
- **New changelist flow**: edit-in-buffer UX with `InsertEnter` autocmd
- **No external dependencies** beyond Telescope

## Target Architecture

See the implementation plan for the full target. Key structural changes:

1. **`executor.lua`** — single async job wrapper, all p4 calls route through it
2. **`config.lua`** — P4CONFIG auto-detection, environment merging
3. **`health.lua`** — `:checkhealth perfnvim` with 5 diagnostic checks
4. **`state.lua`** — job tracking, cache invalidation, sign timer debouncing
5. **`signs.lua`** — extracted sign logic with delta computation (no full-gutter redraw)
6. **`ui.lua`** — floating window helpers with sensible defaults
7. **`notify.lua`** — standardised notification/error display

## Line Count Targets

| Module | Current | Target | Delta |
|---|---|---|---|
| `commands.lua` | 320 | ~200 | Split into ui + pickers |
| `executor.lua` | — | ~120 | New |
| `config.lua` | — | ~100 | New |
| `health.lua` | — | ~80 | New |
| `signs.lua` | — | ~100 | Extracted from change_helpers |
| `state.lua` | — | ~60 | New |
| `ui.lua` | — | ~80 | New |
| `notify.lua` | — | ~40 | New |
| `pickers.lua` | — | ~150 | Extracted from commands |
| **Total** | **664** | **~1,400** | +736 |