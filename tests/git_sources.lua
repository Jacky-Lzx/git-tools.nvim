vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local root = vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()
local helpers = dofile(root .. "/tests/helpers.lua")
local git, repository = require("git_tools.git"), require("git_tools.repository")
local acquire = require("git_tools.diff.sources").git
local f = helpers.fixture()
local old = { "local function outer()", "  local t = {", "    1,", "  }", "  return t", "end" }
f:write("old.lua", old)
f:git("add", ".")
f:git("commit", "-qm", "before")
local staged = vim.deepcopy(old)
table.insert(staged, 2, "  -- inserted")
staged[#staged] = "end -- staged"
f:write("old.lua", staged)
f:git("add", ".")
local disk = vim.deepcopy(staged)
disk[3] = "  local t = { 2,"
f:write("old.lua", disk)
local function sources(lines)
  local result
  acquire(git.task(), f.root, lines, function(value)
    result = value
  end)
  helpers.wait(function()
    return result ~= nil
  end)
  return result
end
local patch = f:git("diff", "--cached", "--no-color")
local snapshot = sources(git.lines(patch))[1]
assert(
  vim.deep_equal(snapshot.before, old) and vim.deep_equal(snapshot.after, staged),
  "Staged snapshots must ignore different disk contents"
)
f:bytes("old.lua", "completely different disk now\n")
snapshot = sources(git.lines(patch))[1]
assert(vim.deep_equal(snapshot.after, staged), "Historical patch reconstruction must never read current disk")
local work = vim.deepcopy(staged)
work[3] = "  local t = { 3,"
f:write("old.lua", work)
patch = f:git("diff", "--no-color")
snapshot = sources(git.lines(patch))[1]
assert(
  vim.deep_equal(snapshot.before, staged) and vim.deep_equal(snapshot.after, work),
  "Working diff must use index as base"
)
f:write("new.lua", { "return {", "  true,", "}" })
local result = f:result("diff", "--no-index", "--", "/dev/null", "new.lua")
snapshot = sources(git.lines(result.stdout))[1]
assert(#snapshot.before == 0 and snapshot.after[2] == "  true,", "Untracked source reconstructs from empty base")
f:git("add", ".")
f:git("commit", "-qm", "after")
f:git("mv", "old.lua", "renamed.lua")
f:write("renamed.lua", { "return true" })
f:git("add", ".")
local snapshots = sources(git.lines(f:git("diff", "--cached", "--no-color")))
assert(next(snapshots), "Renames/deletions/additions must retain text snapshots")
f:cleanup()
print("Git diff snapshots: staged/index, changed disk, worktree, untracked and rename patches passed")
vim.cmd("qa!")
