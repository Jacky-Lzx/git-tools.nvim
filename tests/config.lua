vim.opt.rtp:prepend(vim.fn.getcwd())
local api = vim.api
local git = require("git_tools")
local store = require("git_tools.config").instance()
assert(git.get_config == nil and git.dispose == nil and type(git._dispose) == "function")

local function rejects(fn, message, ...)
  local ok, err = pcall(fn, ...)
  assert(not ok and tostring(err):find(message, 1, true), tostring(err))
end

local commands, handlers = api.nvim_get_commands({}), api.nvim_get_autocmds({})
local defaults = store:get()
assert(defaults.buffer.signs == false and defaults.diff.wrap == false and defaults.command.default == "menu")
assert(defaults.lazygit.width == 0.9)
assert(defaults.compare.keymap.panel.q == "close")
assert(not package.loaded["git_tools.commands"] and not package.loaded["git_tools.lazygit"])
assert(not git.get_state().initialized and vim.deep_equal(api.nvim_get_commands({}), commands))
assert(vim.deep_equal(api.nvim_get_autocmds({}), handlers))
defaults.buffer.signs = true
assert(store:get("buffer", "signs") == false, "A default snapshot must be detached")

rejects(git.toggle, "buffer.signs must be boolean", "signs", "yes")
assert(not git.get_state().signs)
local buffers = require("git_tools.buffer")
local function on_attach() end

local opts = {
  buffer = { debounce = 75, on_attach = on_attach },
  diff = { wrap = true },
  lazygit = { args = { "--example" } },
  compare = { panel_keys = { close = "Q", refresh = false } },
}
local original = vim.deepcopy(opts)
git.setup(opts)
assert(
  not package.loaded["git_tools.diff.window"] and not package.loaded["git_tools.lazygit"],
  "Setup must defer feature loading"
)
local window = require("git_tools.diff.window")
assert(window.options().wrap and not window.options({ wrap = false }).wrap)
rejects(git.setup, "diff.wrap must be boolean", { diff = { wrap = "yes" } })
assert(vim.deep_equal(opts, original), "Setup must retain the caller's legacy options")
assert(store:get("buffer", "numhl") == true and store:get("buffer", "debounce") == 75)
assert(store:get("buffer", "on_attach") == on_attach)
assert(store:get("diff", "wrap") == true and window.options().wrap == true)
assert(store:get("lazygit", "width") == 0.9 and store:get("lazygit", "args", 1) == "--example")
assert(store:get("compare", "panel_keys") == nil)
assert(vim.deep_equal(store:get("compare", "keymap", "panel"), {
  ["<CR>"] = "open",
  ["<Tab>"] = "next_file",
  Q = "close",
}))
opts.lazygit.args[1] = "changed"
local args = store:get("lazygit", "args")
args[1] = "also changed"
assert(store:get("lazygit", "args", 1) == "--example", "Reads must not expose the saved configuration")

assert(git.toggle("signs", true) and git.get_state().signs and store:get("buffer", "signs") == true)
assert(git.toggle("numhl") == false and store:get("buffer", "numhl") == false)
assert(git.toggle("word_diff") and store:get("buffer", "word_diff") == true)
assert(git.toggle("line_blame") and store:get("buffer", "line_blame") == true)
local snapshot = store:get()
local debounce_path = { "buffer", "debounce" }
store:validate(debounce_path, 0)
store:validate(debounce_path, 0.5)
local debounce_error = "buffer.debounce must be a finite number greater than or equal to 0"
rejects(store.validate, debounce_error, store, debounce_path, math.huge)
rejects(git.setup, debounce_error, { buffer = { debounce = -1 } })
rejects(git.setup, "buffer.on_attach must be function", { buffer = { on_attach = false } })
rejects(git.setup, "buffer must be a table or false", { buffer = true })
rejects(git.setup, "buffer.signs must be boolean", { buffer = { signs = "yes" } })
rejects(git.setup, "lazygit.command must be string", { lazygit = { command = false } })
rejects(git.setup, "lazygit.args [2] must be string", { lazygit = { args = { "--example", false } } })
rejects(git.setup, "lazygit.cwd must be string", { lazygit = { cwd = false } })
rejects(git.setup, "lazygit.width must be a positive fraction or integer", { lazygit = { width = 1.5 } })
rejects(git.lazygit, "lazygit.args must be a list", { args = { ["--example"] = true } })
rejects(git.lazygit, "lazygit.cwd must be string", { cwd = 42 })
rejects(git.lazygit, "lazygit.height must be a positive fraction or integer", { height = 0 })
rejects(git.toggle, "buffer.signs must be boolean", "signs", "yes")
rejects(git.toggle, "buffer.debounce must be boolean to toggle", "debounce", 200)
assert(buffers.config.signs == true and buffers.config.debounce == 75)
assert(vim.deep_equal(store:get(), snapshot), "Invalid setup must not publish a new snapshot")

local echo, message = api.nvim_echo
api.nvim_echo = function(chunks)
  message = chunks[1][1]
end
vim.o.wildoptions = ""
assert(vim.deep_equal(vim.fn.getcompletion("GitTools config buffer.si", "cmdline", true), { "buffer.signs" }))
vim.cmd("GitTools config buffer.signs")
assert(message == "true")
git.toggle("signs", false)
assert(not git.get_state().signs and store:get("buffer", "signs") == false)
snapshot.buffer.signs = false
vim.cmd("GitTools config buffer.signs")
assert(message == "false")
vim.cmd("GitTools config diff.wrap")
assert(message == "true")
vim.cmd("GitTools config missing.path")
assert(message == "nil")
vim.cmd("GitTools config")
assert(message == vim.inspect(snapshot))
api.nvim_echo = echo

local buf = api.nvim_create_buf(false, true)
buffers.states[buf] = { buf = buf, name = "", hunks = {}, index = {} }
local observed
api.nvim_create_autocmd("User", {
  pattern = "GitToolsUpdate",
  once = true,
  callback = function()
    observed = store:get("buffer", "signs")
    git.toggle("signs", false)
  end,
})
rejects(git.toggle, "buffer.signs must be boolean", "signs", 1)
assert(observed == nil and buffers.config.signs == false)
assert(git.toggle("signs", true) and observed == true)
assert(buffers.config.signs == false and store:get("buffer", "signs") == false)
buffers.detach(buf)
api.nvim_buf_delete(buf, { force = true })

git.setup({
  buffer = false,
  compare = { keymap = { panel = {} }, panel_keys = { close = "R", refresh = "R" } },
  diff = false,
  lazygit = false,
})
assert(store:get("buffer") == false and store:get("buffer", "signs") == nil)
assert(store:get("diff", "wrap") == false and vim.deep_equal(store:get("lazygit", "args"), {}))
assert(vim.deep_equal(store:get("compare", "keymap", "panel"), {}))
assert(#require("git_tools.compare_config").panel_keymap == 0)
assert(#vim.fn.getcompletion("GitTools config buffer.", "cmdline", true) == 0)
assert(git.toggle("signs", true) and store:get("buffer") == false)
rejects(git.toggle, "buffer.signs must be boolean", "signs", "no")
assert(buffers.config.signs == true and store:get("buffer") == false)
assert(git.toggle("signs") == false and buffers.config.signs == false and store:get("buffer") == false)

git.setup()
assert(store:get("buffer", "debounce") == 100 and store:get("compare", "keymap", "panel", "q") == "close")
assert(store:get("buffer", "signs") == false and store:get("buffer", "numhl") == true)
git.setup({ diff = { wrap = true } })
git.toggle("signs", true)
git._dispose()
assert(store:get("diff", "wrap") == false and window.options().wrap == false and not git.get_state().initialized)
assert(store:get("buffer", "signs") == false)
print("GitTools configuration: cold defaults, legacy aliases, snapshots, runtime state and command inspection passed")
