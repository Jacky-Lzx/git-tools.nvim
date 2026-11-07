# git-tools.nvim

Git pickers use selection-tools path, time and text components. Shared `component_defaults` apply; displayed dates remain searchable. `opts.picker.components` replaces the row recipe (including `{}` or `false`). An explicit `opts.picker.format_item` selects legacy formatting unless components are also supplied.

Git workflows and reusable text diff generation and rendering.

## Features

- Review repository changes, history, blame, branches and stashes.
- Stage and inspect buffer hunks and multi-file diffs.
- Embed text previews independently of Git repositories.

## Requirements

Neovim **0.10+**. Git workflows require Git. Pickers use optional selection-tools.nvim; delta and Lazygit are optional.

## Installation

With lazy.nvim:

```lua
{
  "Jacky-Lzx/git-tools.nvim",
  main = "git_tools",
  dependencies = { "Jacky-Lzx/selection-tools.nvim" },
  opts = {},
}
```

Or put this repository and its required dependencies on `runtimepath`, then call:

```lua
require("git_tools").setup({})
```

## Usage

```vim
:lua require("git_tools").status()
```

## Documentation

- [Complete reference](doc/git-tools.txt) — `:help git-tools`.
- [Workflow and integration guide](doc/guide.md).

## Development

Run from the repository root:

```sh
python3 tests/run.py unit --filter docs
python3 tests/run.py default
```

See [the test workflow](tests/README.md) for dependencies, optional suites and
retained failure evidence. Local development overrides belong in your package
manager configuration; public installation uses the repository above.

[License](LICENSE).
