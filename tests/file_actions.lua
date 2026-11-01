local root = vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local test = dofile(root .. "/tests/helpers.lua")
local git, repository, operations =
  require("git_tools.git"), require("git_tools.repository"), require("git_tools.operations")
local f = test.fixture()
local function status()
  local task = git.task()
  local repo = test.await(function(cb)
    git.discover(task, { cwd = f.root }, cb)
  end)
  return test.await(function(cb)
    repository.status(task, repo, cb)
  end)
end
local function act(name, items, opts)
  return test.await(function(cb)
    operations.files(name, items, opts, cb)
  end)
end
-- Unborn index entries can be unstaged without removing files from disk.
f:write("new.txt", { "new" })
act("stage", status())
assert(f:git("show", ":new.txt") == "new\n")
act("unstage", status())
assert(f:git("ls-files") == "" and vim.fn.filereadable(f.root .. "/new.txt") == 1)
f:git("add", ".")
f:git("commit", "-qm", "initial")
local special = "-space \t\n中.txt"
f:write("new.txt", { "disk" })
f:write(special, { "literal" })
vim.cmd.edit(f.root .. "/new.txt")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
act("stage", status())
assert(f:git("show", ":new.txt") == "disk\n" and f:git("show", ":" .. special) == "literal\n")
act("unstage", status())
assert(f:git("diff", "--cached") == "")
local items = status()
local tracked
for _, item in ipairs(items) do
  if item.path == "new.txt" then
    tracked = item
  end
end
local err = test.result(function(cb)
  operations.files("restore", { tracked }, {
    confirm = function()
      return true
    end,
  }, cb)
end)
assert(err:find("Unsaved buffer", 1, true) and vim.fn.readfile(f.root .. "/new.txt")[1] == "disk")
vim.cmd.bwipeout({ bang = true })
local cancelled = act("restore", { tracked }, {
  confirm = function()
    return false
  end,
})
assert(cancelled == false and vim.fn.readfile(f.root .. "/new.txt")[1] == "disk")
-- A change while confirmation is displayed must not be discarded.
err = test.result(function(cb)
  operations.files("restore", { tracked }, {
    confirm = function()
      f:write("new.txt", { "changed during prompt" })
      return true
    end,
  }, cb)
end)
assert(err:find("changed", 1, true) and vim.fn.readfile(f.root .. "/new.txt")[1] == "changed during prompt")
for _, item in ipairs(status()) do
  if item.kind == "unstaged" then
    tracked = item
  end
end
act("restore", { tracked }, {
  confirm = function()
    return true
  end,
})
assert(vim.fn.readfile(f.root .. "/new.txt")[1] == "new")
-- Stale index snapshots reject an operation even if XY status is unchanged.
f:write("new.txt", { "v1" })
items = status()
f:git("add", "new.txt")
err = test.result(function(cb)
  operations.files("stage", items, {}, cb)
end)
assert(err and err:find("changed", 1, true))
f:cleanup()
print(
  "git file actions: multi-file disk staging, unborn unstage, literal paths, discard cancel and stale/unsaved guards passed"
)
vim.cmd("qa!")
