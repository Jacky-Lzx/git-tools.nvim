# git-tools.nvim

Reusable diff generation and preview rendering for Neovim. This first version
provides a diff core; it does not add Git status, staging, log or commit commands.

The core compares ordinary text and unsaved contents, including outside Git
repositories. It has no selection-tools, Snacks, LSP or Git executable dependency.
An optional adapter makes it a preview provider for selection-tools.nvim.

## Requirements and local installation

- Neovim 0.10+ APIs; currently validated with Neovim 0.12.6.
- Optional `delta` for ANSI diff rendering; unavailable or failed delta falls
  back to native diff highlighting.
- Optional selection-tools.nvim for picker windows.

This repository is currently a local plugin. With lazy.nvim:

```lua
{
  dir = vim.fn.expand("~/Documents/Github/nvim_plugins/git-tools.nvim"),
  name = "git-tools.nvim",
  main = "git_tools",
  lazy = true,
}
```

Point `dir` at your checkout. No `setup()` call is needed. Requiring the module
installs no mappings, commands, autocmds or processes.

## Generate a patch

```lua
local diff = require("git_tools.diff")
local patch = diff.unified(
  { "local timeout = 1000" },
  { "local timeout = 3000" },
  { old_path = "client.lua", new_path = "client.lua", context = 3 }
)
```

`unified(before, after, opts)` returns a list of unified diff lines, including
`---` and `+++` labels. Identical inputs return `{}`. Inputs may be strings or
lists of lines. Strings retain exact final-newline semantics; array entries are
newline-free strings representing terminated lines. An empty array represents
empty text. Inputs are never modified, and no buffers or files are created.

Labels default to `before` and `after`; when only `old_path` is set, both labels
use it. `context` defaults to 3 and accepts a nonnegative integer.

## Render into a host preview

```lua
local handle = require("git_tools.diff").render(view, patch, {
  backend = "delta", -- "vim" or "delta"; default "vim"
  cwd = project_root,
  delta = { command = "delta", args = {}, timeout = 2000 },
})
-- handle:resize() renders again using the preview's current width.
-- handle:close() cancels work; the host releases adopted buffers.
```

The host supplies this view contract:

| Member | Responsibility |
| --- | --- |
| `win` | The existing preview window ID |
| `is_cancelled()` | Whether this preview request is obsolete |
| `set_lines(lines, ft, title)` | Publish guarded text and release any previous owned frame |
| `set_buffer(buf, metadata)` | Adopt a ready frame; return false if obsolete |

For ANSI output, `metadata = { owned = true, title = ... }`. The host owns the
adopted buffer and deletes it on replacement or close, including a rejected frame.
Git-tools owns delta processes, cancellation and render generations. It creates
no windows. Calls and publication run on Neovim's main thread. An optional fourth
argument `valid()` supplies an additional caller-specific validity check.

Delta receives literal argv, stdin and a bounded timeout. Paging is disabled;
width and dark/light mode follow the preview. Missing delta, spawn errors, failure,
empty output, terminal-render errors and timeouts fall back to native diff.
Command-only and file-operation summaries bypass delta. Late output is ignored.

## Use with selection-tools

```lua
require("selection_tools").open({
  prompt = "Review changes",
  items = { { text = "client.lua", lines = patch, root = project_root } },
  format_item = function(item) return item.text end,
  resume = false,
  preview = {
    enabled = true,
    providers = {
      require("git_tools.integrations.selection").diff({ backend = "delta" }),
    },
  },
})
```

The adapter reads `item.lines` or `opts.lines(item)` and uses `opts.cwd` or
`item.root`. It returns false for items without a patch so another provider can
handle them. Loading the adapter does not import selection-tools.

selection-tools retains ownership of layout, input, focus, preview buffers and
confirmation. Callers such as lsp-tools retain edit interpretation, version
validation and application. Generating or rendering a diff never applies edits.

## Migration

Replace `selection_tools.providers.diff.provider(opts)` with
`git_tools.integrations.selection.diff(opts)`. Direct render callers use
`git_tools.diff.render(view, lines, opts, valid)` and pass `opts.cwd` explicitly.
selection-tools no longer contains a diff provider or depends on git-tools.
Install this local checkout alongside consumers until a remote release exists.

## Validation

```sh
sh tests/run.sh
# Optional picker integration uses the sibling selection-tools.nvim checkout:
SELECTION_TOOLS_DIR=/path/to/selection-tools.nvim sh tests/run.sh
```

Tests cover Unicode, insert/delete, exact final newlines, pure generation,
native/ANSI rendering, literal arguments, timeout/error fallback, cancellation,
resize generations, and optional picker frame ownership. The rendering core
tests do not import a picker or run Git. Picker integration uses real delta when
installed. Consumer LSP and terminal workflows are covered in lsp-tools.nvim.

MIT licensed. The renderer originated in selection-tools.nvim; its MIT copyright
notice is retained in [LICENSE](LICENSE).
