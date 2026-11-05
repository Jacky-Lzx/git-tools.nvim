# git-tools.nvim

Git workflows and reusable diff generation/preview rendering for Neovim.
The text diff core remains independent of Git and works outside repositories.

The core compares ordinary text and unsaved contents, including outside Git
repositories. It has no selection-tools, Snacks, LSP or Git executable dependency.
An optional adapter makes it a preview provider for selection-tools.nvim.

## Requirements and local installation

- Neovim 0.10+ APIs; currently validated with Neovim 0.12.6.
- Native Lua previews by default, with optional theme-tools.nvim palette sync.
- Optional `delta` for ANSI rendering; unavailable or failed delta falls back
  to the native renderer.
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

Point `dir` at your checkout. Query APIs need no `setup()` call. Requiring the
module installs no mappings, commands, autocmds or processes. `setup()` enables
buffer tracking and the `:GitTools` command; it never installs global mappings.

## Repository changes

```lua
require("git_tools").status() -- native preview; backend = "delta" remains available
require("git_tools").status({ native = { layout = "side_by_side" } }) -- optional left/right preview
require("git_tools").status({ native = { layout = "top_bottom" } }) -- optional before/after blocks
-- Optional: cwd = "/project", kind = "staged" | "unstaged" | "untracked"
```

Requires Git and selection-tools.nvim. Lists index and working-tree changes
separately, including untracked files and conflicts. Type to filter, select a
file to edit it, or use the picker's standard quickfix/split actions. The preview
shows the selected Git patch, including binary summaries; it compares disk to
index, and index to HEAD, rather than silently including unsaved buffers.
The default repository follows the current file (falling back to cwd for unnamed
buffers); explicit `cwd` selects another repository. Linked worktrees and unusual
filenames are supported. Queries/previews are asynchronous, bounded by a timeout,
and cancelled on close or selection changes. `picker = { ... }` customizes the
optional selection-tools UI. The picker dependency loads only when invoked.
The changes picker supports multi-selection: `<C-s>` stages disk files,
`<C-z>` unstages them, `<C-r>` confirms discarding tracked unstaged disk changes,
and `<F5>` refreshes. Operations retain the picker and query. Mixed incompatible
selections, conflicts, stale index/file snapshots and discarding an unsaved
buffer are rejected. Untracked files are never deleted by Discard. These file
actions use disk content; the buffer hunk APIs below use unsaved buffer text.

`require("git_tools").changes()` (or `:GitTools changes`) starts with individual
repository hunks. `<F4>` switches between file and hunk results without losing
the query. The same action keys apply to selected hunks; a multi-hunk selection
is submitted as one ordered Git patch. Confirm jumps to the first changed line,
mapping disk/index coordinates through any unsaved buffer changes. Binary and
metadata-only results use whole-file operations; select those separately from
text hunks. Conflict files use the merge view. `kind` filters either view.

## History and blame

```lua
local git = require("git_tools")
git.log({ limit = 200 })             -- repository log; optional rev = "main"
git.file_history()                   -- follows renames of the current file
git.line_history({ range = { 5, 12 } }) -- Git -L history; defaults to cursor line
git.blame()                         -- current buffer line, including unsaved edits
git.blame({ range = { 5, 12 } })
```

History and blame entries preview their complete commit patch. Confirm opens it
in a read-only tab (`q` closes). Uncommitted blame entries display buffer text
and do not pretend to identify a commit. `cwd` and absolute `path` can target
another file; explicit `path` blames disk content. File history follows renames;
line history uses Git's `-L` semantics and committed line numbers. History results
are bounded by `limit` (default 200); increase it explicitly when needed.

## Remote links

```lua
require("git_tools").browse() -- cursor commit, current file permalink, or repo
require("git_tools").browse({ copy = true, range = { 5, 12 } })
require("git_tools").browse({ permalink = false }) -- current branch (detached: SHA)
require("git_tools").browse({ commit = "HEAD~1" }) -- commit page
require("git_tools").browse({ what = "repo" }) -- repository home
require("git_tools").browse({ what = "branch" }) -- current or explicit branch
```

The default auto target recognizes a valid commit hash under the cursor,
otherwise links the current file (or repository home without a file). A line
range always selects a file link. Explicit `what` accepts `repo`, `branch`,
`file`, `commit` or `permalink`; file/permalink targets avoid hash detection.
With multiple remotes, a chooser lists the upstream/origin first; `remote`
selects directly, and `select_remote=false` uses the preferred remote directly.
Supports
GitHub, GitLab, Bitbucket and Codeberg/Gitea, HTTP(S), SSH and scp-style remotes.
Private hosts can specify `provider`, `base_url`, or `url(remote,rev,path,opts)`.
Paths/revisions are URL encoded and URL credentials are discarded. File links
require tracked files; line ranges refer to remote committed content, so unsaved
insertions can shift their meaning. `browse(opts, callback)` returns the URL via
`callback(err,url)` instead of opening/copying it. No remote request is made by Git.

## Branches and stash

```lua
require("git_tools").branches({ all = true }) -- locals and remote refs
require("git_tools").stash() -- preview then Enter applies, retaining the stash
-- Also :GitTools branches / :GitTools stash
```

The branch picker previews recent commits. Enter switches branches; selecting a
remote branch creates a local tracking branch (an existing local name is never
overwritten). `<C-a>` prompts to create a branch at HEAD, `<C-d>` confirms deleting
a merged local branch, and `<F5>` refreshes. Creation does not switch. Current,
worktree-checked-out, remote and unmerged branches cannot be deleted here. Branch
tips are revalidated before mutations. `start` customizes the creation revision.

Stash entries preview complete patches, including untracked files. Enter applies
the selected immutable stash object, even if its `stash@{n}` position changed.
The entry must still exist; apply never drops it. `index=true` also restores index
state. Conflicts are reported and retained for `merge()` to resolve. `<F5>` reloads
the list. Switching branches/applying stash refuses unsaved repository buffers;
Git handles conflicts with existing disk changes without forcing a checkout.

## Lazygit floating terminal

```lua
require("git_tools").lazygit()
-- Optional cwd, command, args={}, env={}, width=0.9, height=0.9, border="rounded"
-- Also available after setup(): :GitTools lazygit
```

Requires the external `lazygit` executable. Opens a centered terminal in the
current file's directory (editor cwd for unnamed/special buffers). LazyGit finds
the repository itself. Repeated calls focus the existing session. `<C-g>` closes
the float from terminal or Normal mode; Normal-mode `q` also closes it. Escape and
other terminal keys pass through to LazyGit. Closing stops the job and releases
the terminal buffer; successful exit closes automatically, while failure output
remains visible. Resizing follows the editor, and closing refreshes file/index
state without discarding unsaved buffers. No Snacks or picker dependency.
Returns a session with `buf`, `win`, `job` and `:close()`/`:resize()` methods.
`setup({ lazygit = { ... } })` optionally sets launcher defaults. Arguments use
literal argv; the launcher inherits LazyGit's existing configuration unchanged.

## Buffer hunks and overlay

```lua
local git = require("git_tools")
git.setup({ buffer = { signs = false, numhl = true, word_diff = false } })
git.nav_hunk("next") -- prev, first, last
git.select_hunk() -- synchronous visual/operator mapping; buffer must be ready
git.preview_hunk()
git.toggle_overlay()
git.stage_hunk({ range = { 5, 8 } }) -- optional; default hunk under cursor
git.unstage_hunk()
git.reset_hunk()
git.stage_buffer() -- also unstage_buffer(), reset_buffer()
git.quickfix() -- current buffer; { all = true } for repository disk/index hunks
git.toggle("word_diff") -- also signs, numhl, line_blame
```

`setup()` opts into buffer tracking; requiring the module alone still has no
side effects. Diffs compare index with unsaved buffer text. Stage writes selected
buffer changes to the index without saving disk; unstage restores selected index
changes from HEAD. Reset changes only buffer text and is undoable. Visual ranges
project only selected replacement/addition lines; excess old lines in an unequal
replacement belong to its final new line. Entire-file methods cover every hunk.
Index patches retain file modes and final-newline semantics, use context checks,
and recheck the index/buffer snapshot before applying. CRLF index lines retain
CRLF. Binary, symlink and unmerged entries are excluded from text hunk operations.
Only regular file content is staged; attributes/clean filters are not executed.
Each mutation accepts `callback(err)`. Repeated index mutations are rejected.

Index watchers (plus a 500ms inode poll for coalesced filesystem events) and
buffer/focus events refresh attached buffers. Debounce defaults to 100ms.
`buffer.on_attach(buf)` optionally installs your buffer-local mappings once the
first repository snapshot is ready.
`GitToolsUpdate` User events carry `data.buf`; `vim.b.git_tools_status` contains
added/changed/removed/head. `GitToolsAdd/Change/Delete` highlight groups support
statuscolumn patterns; add `"GitTools"` to Snacks' Git patterns. Optional adapters:

```lua
local status = require("git_tools.integrations.status")
-- lualine: { "diff", source = status.diff }, branch component: status.branch
status.scrollbar() -- register after nvim-scrollbar.setup(); gitsigns handler off
```

## Multi-file diffs and merge conflicts

```lua
local git = require("git_tools")
git.compare() -- file panel with staged (HEAD/index) and unstaged (index/buffer)
git.compare({ from = "main", to = "HEAD" }) -- resolved revisions, read-only sides
git.compare({ commit = "HEAD" }) -- compare commit to first parent; root supported
git.diffthis() -- current file, index/buffer; git.diffthis("HEAD~1") for revision
git.toggle_compare()
git.merge() -- conflicted files only, ours / editable result / theirs
```

Each view owns a tab with a file panel and native Neovim diff windows. Panel
`<CR>` selects a file, `R` reloads the list; `<leader>gp` returns from a diff pane
to the panel, and `q` closes the view. Revision/index panes are read-only; working
panes use existing buffers and preserve unsaved changes on close. Native `]c`,
`[c`, diff folds and `do`/`dp` remain available subject to buffer writability.
History pickers use `<C-d>` to open the selected commit in this view.

In the merge result, `]x`/`[x` navigate conflicts; `co`/`ct`/`cb` choose ours,
theirs or both for the current conflict, including diff3-style base markers.
`<leader>gb` opens the base snapshot. These edits are undoable and do not stage.
`S` explicitly saves and stages the result; remaining markers block that action.
Result edits survive closing the view. Delete/modify cases expose absent sides
as empty snapshots; deleting a result remains an explicit external Git action.
All view mappings are released on close. Views are loaded on demand; `R` is the
explicit file-panel refresh (buffer hunk tracking refreshes independently).

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
  backend = "native", -- default; "delta" or plain "vim" also available
  cwd = project_root,
  native = {
    layout = "unified", -- default; also "side_by_side" or "top_bottom"
    line_numbers = true,
    file_header = true,
    syntax = true,
    word_diff = true,
    -- ft = "lua", -- override filetype inferred from patch labels
  },
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
Git-tools owns delta processes, cancellation, render generations and temporary
hidden preparation windows. ANSI output is prepared at the preview's dimensions
and adopted only after terminal text is ready, so the host keeps its previous
frame during rendering. Preparation windows and unadopted buffers are released
on publication, cancellation, resize, failure or timeout. The host owns its visible
preview window and adopted buffers. Calls and publication run on Neovim's main
thread. An optional fourth argument `valid()` supplies an additional caller-specific
validity check.

The default native renderer prepares a normal, read-only scratch buffer and
publishes it with the same `set_buffer` ownership contract. It shows compact
file/hunk headings, old/new line numbers, addition/deletion backgrounds and
multiple UTF-8-safe inline change spans. Gutters and hunk rules are virtual:
copying code lines does not copy line numbers or `+`/`-` markers. Resize updates
rules in place, preserving the preview buffer and scroll position. Summaries
without text hunks use `set_lines`; `backend = "vim"` retains raw patch text.
Frame metadata also identifies the actual `backend` (`"native"` or `"delta"`),
including when a requested delta preview falls back to native rendering.

Set `native.layout = "side_by_side"` to show the old version on the left and
the new version on the right. This is opt-in for render calls, Git picker
options, `preview_hunk()` and the selection adapter; the default stays
`"unified"`. Replacement lines align across columns, with empty cells for
insertions/deletions. Both columns retain syntax, decorations and inline diff
emphasis. Tabs expand independently and long lines end with `…`; resizing
reflows the same buffer and preserves its view. Very narrow previews temporarily
use unified layout and return to columns when widened. The side-by-side buffer
contains both visible code columns and padding; gutters remain virtual.

Set `native.layout = "top_bottom"` for stacked before/after blocks within each
hunk: the complete old hunk appears above the new one, each with its own context
and line numbers. `Before` / `After` headings separate the blocks, and an empty
side shows `(empty)`. Both blocks retain full code lines, syntax, decorations
and inline emphasis; copying a code line excludes gutters. This layout uses
the same host buffer and resize/ownership contract, and is available through
the same render, picker, hunk-preview and selection-adapter options.

When theme-tools is loaded, native colors subscribe to its semantic palette,
including overrides and live theme changes. Without it, standard editor
highlights supply the colors. Code syntax uses installed Tree-sitter parsers
and queries. Pass `sources` to render each side from its complete document,
then project captures onto visible diff lines. Git picker previews acquire the
base blob identified by the patch and reconstruct its result without reading
the current working tree. Missing parsers leave plain code with diff colors;
patch-only callers retain snippet highlighting. Stale snapshots whose visible
text does not match fall back to snippets for that side.

`diff.unified(before, after, opts)` also returns a second value, a captured
`{ before = lines, after = lines, ft = opts.ft }` snapshot. Supply it as
`diff.render(view, patch, { sources = { snapshot } })`. For concatenated patches,
provide one entry per `---`/`+++` file section, in patch order, including repeated
edits of the same path. A file's hunks share one parse per side. The optional
selection adapter accepts `item.sources` too.

Full-document previews also project rainbow bracket colors when pairs.nvim is
already loaded and enabled. They never load or configure pairs. Set
`native.decorations = false` to disable this, or supply
`native.highlights = function(lines, ft) return spans end` for a custom provider.
Each span uses zero-based byte `row`, `col`, `end_col`, `hl_group` and optional
`priority`; inline diff emphasis remains above these decorations.
Native rendering preserves delta's visual conventions rather than interpreting
delta themes or arguments. Use `native.file_header = false` for compact undo
and LSP previews. Delta options apply only to `backend = "delta"`.

Native previews are limited to 10,000 patch lines / 1 MiB and visibly indicate
truncation (`metadata.truncated = true`). Syntax work is capped at 128 documents/snippets,
200 KB and 30,000 highlight spans; inline matching is bounded to replacement
blocks of 32 lines per side and lines of 4 KB. Larger changes retain line-level
backgrounds. Delta remains an option for its exact syntax/theme behavior and
its own side-by-side layout (`delta.args = { "--side-by-side" }`).

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
      require("git_tools.integrations.selection").diff(),
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
python3 tests/tui.py
python3 tests/native_tui.py
GIT_TOOLS_LAYOUT=side_by_side python3 tests/native_tui.py
GIT_TOOLS_LAYOUT=top_bottom python3 tests/native_tui.py
# Optional picker integration uses the sibling selection-tools.nvim checkout:
SELECTION_TOOLS_DIR=/path/to/selection-tools.nvim sh tests/run.sh
```

Tests cover Unicode, insert/delete, exact final newlines, pure generation,
native/ANSI rendering, literal arguments, timeout/error fallback, cancellation,
resize generations, and optional picker frame ownership. The rendering core
tests do not import a picker or run Git. Picker integration uses real delta when
installed. Consumer LSP and terminal workflows are covered in lsp-tools.nvim.

The Git fixture suite covers repository paths/worktrees, history/blame/links,
partial index operations, unsaved buffers, newline preservation, external index
updates, native comparison tabs and real merge conflicts. `tests/tui.py` drives
continuous keyboard input, overlay, Visual staging and operator-pending `dih`.
With selection-tools installed, it also exercises picker filtering, file/hunk
switching and disk staging while preserving unsaved buffer edits.
Set `GIT_TOOLS_CONFIG=/path/to/nvim` to exercise its git-tools keymap spec too.
When LazyGit is installed, this TUI check also opens its real interface using an
isolated configuration directory and verifies resize, close/reopen and quit.
That part needs normal terminal access (`/dev/tty`).

MIT licensed. The renderer originated in selection-tools.nvim; its MIT copyright
notice is retained in [LICENSE](LICENSE).
