vim.opt.rtp:prepend(vim.fn.getcwd())
local api = vim.api
local git = require("git_tools")

git.dispose()
assert(not package.loaded["git_tools.commands"], "Cold disposal must not load the command module")
assert(not api.nvim_get_commands({}).GitTools)

local calls = 0
git.status = function(args)
  assert(vim.deep_equal(args, {}))
  calls = calls + 1
end

local opts = { buffer = false, command = { default = "status" } }
git.setup(opts)
git.setup(opts)
assert(not package.loaded["git_tools.revisions"], "Command registration must not load revision completion")
vim.cmd.GitTools()
assert(calls == 1, "The default action must dispatch after repeated setup")

local buf = api.nvim_create_buf(false, true)
api.nvim_buf_create_user_command(buf, "GitTools", function()
  calls = calls + 10
end, {})
git.dispose()
assert(not api.nvim_get_commands({}).GitTools)
api.nvim_buf_call(buf, function()
  vim.cmd.GitTools()
end)
assert(calls == 11, "Disposal must preserve user commands in buffer-local scope")
api.nvim_buf_delete(buf, { force = true })

git.setup(opts)
api.nvim_create_user_command("GitTools", function(args)
  assert(args.bang and args.args == "two words")
  calls = calls + 100
end, { bang = true, nargs = "?" })
local foreign = api.nvim_get_commands({}).GitTools
local ok, err = pcall(git.setup, { buffer = { signs = true } })
assert(not ok and tostring(err):find("Command already exists: GitTools", 1, true))
assert(git.get_config("buffer") == false and vim.fn.exists("#GitToolsBuffer") == 0)
git.dispose()
assert(vim.deep_equal(api.nvim_get_commands({}).GitTools, foreign))
vim.cmd("GitTools! two words")
assert(calls == 111, "Disposal must preserve a user command replacing the plugin's registration")
api.nvim_del_user_command("GitTools")

print("GitTools command ownership: cold disposal, repeated setup, buffer scope and external replacement passed")
