vim.opt.rtp:prepend(vim.fn.getcwd())
local api = vim.api
local git = require("git_tools")
local commands, handlers = api.nvim_get_commands({}), api.nvim_get_autocmds({})
local defaults = git.get_config()
assert(defaults.buffer.signs == false and defaults.diff.wrap == false and defaults.command.default == "menu")
assert(defaults.compare.keymap.panel.q == "close")
assert(not package.loaded["git_tools.commands"] and not package.loaded["git_tools.lazygit"])
assert(not git.get_state().initialized and vim.deep_equal(api.nvim_get_commands({}), commands))
assert(vim.deep_equal(api.nvim_get_autocmds({}), handlers))
defaults.buffer.signs = true
assert(git.get_config("buffer", "signs") == false, "A default snapshot must be detached")

local opts = {
  buffer = { debounce = 75 },
  diff = { wrap = true },
  lazygit = { args = { "--example" } },
  compare = { panel_keys = { close = "Q", refresh = false } },
}
local original = vim.deepcopy(opts)
git.setup(opts)
assert(vim.deep_equal(opts, original), "Setup must retain the caller's legacy options")
assert(git.get_config("buffer", "numhl") == true and git.get_config("buffer", "debounce") == 75)
assert(git.get_config("diff", "wrap") == true)
assert(git.get_config("lazygit", "width") == 0.9 and git.get_config("lazygit", "args", 1) == "--example")
assert(git.get_config("compare", "panel_keys") == nil)
assert(vim.deep_equal(git.get_config("compare", "keymap", "panel"), {
  ["<CR>"] = "open",
  ["<Tab>"] = "next_file",
  Q = "close",
}))
opts.lazygit.args[1] = "changed"
local args = git.get_config("lazygit", "args")
args[1] = "also changed"
assert(git.get_config("lazygit", "args", 1) == "--example", "Reads must not expose the saved configuration")

git.toggle("signs", true)
assert(git.get_state().signs and git.get_config("buffer", "signs") == false)
local snapshot = git.get_config()
assert(not pcall(git.setup, { buffer = { debounce = -1 } }))
assert(vim.deep_equal(git.get_config(), snapshot), "Invalid setup must not publish a new snapshot")

local echo, message = api.nvim_echo
api.nvim_echo = function(chunks)
  message = chunks[1][1]
end
vim.o.wildoptions = ""
assert(vim.deep_equal(vim.fn.getcompletion("GitTools config buffer.si", "cmdline", true), { "buffer.signs" }))
vim.cmd("GitTools config buffer.signs")
assert(message == "false")
vim.cmd("GitTools config diff.wrap")
assert(message == "true")
vim.cmd("GitTools config missing.path")
assert(message == "nil")
vim.cmd("GitTools config")
assert(message == vim.inspect(snapshot))
api.nvim_echo = echo

git.setup({
  buffer = false,
  compare = { keymap = { panel = {} }, panel_keys = { close = "R", refresh = "R" } },
  diff = false,
  lazygit = false,
})
assert(git.get_config("buffer") == false and git.get_config("buffer", "signs") == nil)
assert(git.get_config("diff", "wrap") == false and vim.deep_equal(git.get_config("lazygit", "args"), {}))
assert(vim.deep_equal(git.get_config("compare", "keymap", "panel"), {}))
assert(#require("git_tools.compare_config").panel_keymap == 0)
assert(#vim.fn.getcompletion("GitTools config buffer.", "cmdline", true) == 0)

git.setup()
assert(git.get_config("buffer", "debounce") == 100 and git.get_config("compare", "keymap", "panel", "q") == "close")
git.setup({ diff = { wrap = true } })
git.dispose()
assert(git.get_config("diff", "wrap") == false and not git.get_state().initialized)
print("GitTools configuration: cold defaults, legacy aliases, snapshots, runtime state and command inspection passed")
