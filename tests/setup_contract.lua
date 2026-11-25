vim.opt.rtp:prepend(vim.fn.getcwd())
local plugin = require("git_tools")
local options = { buffer = false }
local caller = vim.deepcopy(options)
plugin.setup(options)
assert(vim.deep_equal(caller, options), "setup mutated caller configuration")
local commands = vim.api.nvim_get_commands({})
local handlers = vim.api.nvim_get_autocmds({})
assert(commands.GitTools, "setup did not register :GitTools")
local function complete(line)
  return vim.fn.getcompletion(line, "cmdline", true)
end
local wildoptions = vim.o.wildoptions
vim.o.wildoptions = ""
assert(#complete("GitTools ") == 18)
assert(vim.deep_equal(complete("GitTools co"), { "compare" }))
assert(vim.deep_equal(complete("set number | GitTools co"), { "compare" }))
assert(vim.deep_equal(complete("GitTools compare"), { "compare" }))
assert(vim.deep_equal(vim.list_slice(complete("silent 1,2GitT compare "), 1, 2), { "HEAD", "HEAD~1" }))
assert(vim.deep_equal(complete("GitTools compare HEAD HEAD~"), { "HEAD~1" }))
assert(vim.deep_equal(complete("GitTools log HEAD~"), { "HEAD~1" }))
assert(#complete("GitTools compare HEAD HEAD~1 ") == 0)
assert(#complete("GitTools log HEAD ") == 0)
assert(#complete("GitTools status ") == 0)
assert(#complete("GitTools cmp") == 0)
vim.o.wildoptions = "fuzzy"
assert(vim.deep_equal(complete("GitTools cmp"), { "compare" }))
vim.o.wildoptions = wildoptions
local stage_hunk = plugin.stage_hunk
local stage_args
plugin.stage_hunk = function(args)
  stage_args = args
end
vim.cmd("1GitTools stage")
plugin.stage_hunk = stage_hunk
assert(vim.deep_equal(stage_args, { range = { 1, 1 } }), "GitTools stage must still dispatch to stage_hunk")
assert(not pcall(plugin.setup, false), "setup(false) must reject an invalid configuration type")
assert(not pcall(plugin.setup, { compare = { panel_keys = { refresh = "" } } }), "setup must reject empty keys")
assert(not pcall(plugin.setup, { compare = { panel_keys = { close = "R" } } }), "setup must reject duplicate keys")
assert(not pcall(plugin.setup, { compare = { keymap = { panel = { o = "unknown" } } } }))
assert(not pcall(plugin.setup, { compare = { keymap = { panel = { o = { [2] = "open" } } } } }))
assert(vim.deep_equal(commands, vim.api.nvim_get_commands({})), "Invalid setup replaced commands")
assert(vim.deep_equal(handlers, vim.api.nvim_get_autocmds({})), "Invalid setup replaced handlers")
plugin.setup(caller)
assert(#vim.api.nvim_get_autocmds({}) == #handlers, "Repeated setup duplicated automatic handlers")

local buffers = require("git_tools.buffer")
plugin.setup({ buffer = { debounce = 75, signs = true } })
local before = vim.deepcopy(buffers.config)
local handlers = vim.api.nvim_get_autocmds({ group = "GitToolsBuffer" })
assert(not pcall(plugin.setup, { buffer = { debounce = -1 } }))
assert(vim.deep_equal(before, buffers.config))
assert(vim.deep_equal(handlers, vim.api.nvim_get_autocmds({ group = "GitToolsBuffer" })))
plugin.setup()
assert(buffers.config.debounce == 100 and not buffers.config.signs)
plugin.setup({ buffer = false })
assert(vim.fn.exists("#GitToolsBuffer") == 0)
plugin.dispose()
plugin.dispose()
assert(not vim.api.nvim_get_commands({}).GitTools, "dispose did not remove :GitTools")
plugin.setup(caller)
assert(vim.api.nvim_get_commands({}).GitTools, "setup did not restore :GitTools after disposal")
plugin.dispose()
print("git-tools.nvim: setup input isolation, invalid configuration and registration lifetime passed")
