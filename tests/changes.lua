local root = vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local test = dofile(root .. "/tests/helpers.lua")
local git, changes = require("git_tools.git"), require("git_tools.changes")
local f = test.fixture()
local original = {}
for i = 1, 32 do
  original[i] = "line " .. i
end
f:write("a.txt", original)
f:git("add", ".")
f:git("commit", "-qm", "initial")
local edited = vim.deepcopy(original)
edited[2], edited[25] = "first change", "second change"
f:write("a.txt", edited)
local task = git.task()
local repo = test.await(function(cb)
  git.discover(task, { cwd = f.root }, cb)
end)
local function query(kind)
  return test.await(function(cb)
    changes.query(task, repo, { kind = kind }, cb)
  end)
end
local function apply(action, items, opts)
  return test.await(function(cb)
    changes.apply(action, items, opts, cb)
  end)
end
local items = query("unstaged")
assert(#items == 2 and items[1].pos[1] < items[2].pos[1])
assert(vim.deep_equal(items[1].sources[1].before, original))
assert(vim.deep_equal(items[2].sources[1].after, edited), "Individual hunks retain the complete result of all changes")
assert(items[1].lnum == 2 and items[2].lnum == 25, "Jump positions must exclude context lines")
assert(not table.concat(items[1].lines, "\n"):find("second change", 1, true))
apply("stage", { items[2] })
local index = f:git("show", ":a.txt")
assert(index:find("line 2\n", 1, true) and index:find("second change", 1, true), "Only selected hunk must be staged")
apply("unstage", query("staged"))
assert(f:git("diff", "--cached") == "")
items = query("unstaged")
apply("stage", { items[2], items[1] })
assert(f:git("show", ":a.txt") == table.concat(edited, "\n") .. "\n")
apply("unstage", query("staged"))
items = query("unstaged")
assert(apply("restore", { items[1] }, {
  confirm = function()
    return false
  end,
}) == false)
apply("restore", { items[1] }, {
  confirm = function()
    return true
  end,
})
assert(
  vim.fn.readfile(f.root .. "/a.txt")[2] == "line 2" and vim.fn.readfile(f.root .. "/a.txt")[25] == "second change"
)
items = query("unstaged")
f:write("a.txt", original)
local err = test.result(function(cb)
  changes.apply("stage", items, {}, cb)
end)
assert(err and err:find("changed", 1, true))
f:bytes("binary", "a\0b\n")
local metadata = query("untracked")
assert(#metadata == 1 and not metadata[1].hunk)
apply("stage", metadata)
assert(f:git("show", ":binary") == "a\0b\n")
f:cleanup()
print(
  "git changes: separate hunks, ordered multi-select stage/unstage, partial discard, stale guards and binary fallback passed"
)
vim.cmd("qa!")
