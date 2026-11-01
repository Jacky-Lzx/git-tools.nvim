local root = vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local test = dofile(root .. "/tests/helpers.lua")
local browse = require("git_tools.browse")
local f = test.fixture()
f:write("file.txt", { "contents" })
f:git("add", ".")
f:git("commit", "-qm", "initial")
f:git("remote", "add", "origin", "git@github.com:owner/project.git")
local function url(opts)
  return test.await(function(cb)
    browse.open(vim.tbl_extend("force", { cwd = f.root, path = f.root .. "/file.txt" }, opts), cb)
  end)
end
assert(url({ what = "repo" }) == "https://github.com/owner/project")
assert(url({ what = "branch" }) == "https://github.com/owner/project/tree/main")
local sha = f:git("rev-parse", "HEAD"):gsub("\n$", "")
assert(url({ word = sha:sub(1, 10) }) == "https://github.com/owner/project/commit/" .. sha)
assert(url({ word = "deadbeef" }):find("/blob/" .. sha .. "/file.txt", 1, true))
assert(url({ word = sha:sub(1, 10), range = { 1, 1 } }):find("/file.txt#L1", 1, true))
f:git("remote", "add", "backup", "https://gitlab.com/group/project.git")
local chosen = false
assert(url({
  what = "repo",
  select_remote = function(names, cb)
    assert(names[1] == "origin" and #names == 2)
    chosen = true
    cb("backup")
  end,
}) == "https://gitlab.com/group/project")
assert(chosen and url({ what = "branch", remote = "backup" }) == "https://gitlab.com/group/project/-/tree/main")
assert(url({
  what = "repo",
  select_remote = function(_, cb)
    cb(nil)
  end,
}) == nil)
f:git("checkout", "--detach", "-q")
local err = test.result(function(cb)
  browse.open({ cwd = f.root, what = "branch" }, cb)
end)
assert(err and err:find("Detached HEAD", 1, true))
assert(url({ what = "file", select_remote = false, permalink = false }):find("/blob/" .. sha, 1, true))
f:cleanup()
print(
  "git browse targets: repository/branch pages, cursor commits, range precedence, multiple remotes, cancel and detached HEAD passed"
)
vim.cmd("qa!")
