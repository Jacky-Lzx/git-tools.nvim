vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local git = require("git_tools.git")
local repository = require("git_tools.repository")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local function command(args)
  local result = vim.system(args, { cwd = root }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
local function run(...)
  return command(vim.list_extend({ "git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null" }, { ... }))
end
run("init", "-q")
run("config", "user.name", "Fixture")
run("config", "user.email", "fixture@example.invalid")
vim.fn.writefile({ "one", "two" }, root .. "/a.txt")
run("add", ".")
run("commit", "-qm", "initial")
vim.fn.writefile({ "staged", "two" }, root .. "/a.txt")
run("add", "a.txt")
vim.fn.writefile({ "staged", "working" }, root .. "/a.txt")
local special = "-special \t\n中.txt"
vim.fn.writefile({ "new" }, root .. "/" .. special)
local function await(start)
  local done, result
  start(function(err, value)
    assert(not err, err)
    result = value
    done = true
  end)
  assert(
    vim.wait(5000, function()
      return done
    end, 5),
    "Git timeout"
  )
  return result
end
local task = git.task()
local repo = await(function(cb)
  git.discover(task, { cwd = root }, cb)
end)
assert(repo.root == root and repo.git_dir == root .. "/.git")
local entries = await(function(cb)
  repository.status(task, repo, cb)
end)
assert(#entries == 3 and entries[1].kind == "staged" and entries[2].kind == "unstaged")
assert(entries[3].path == special)
for _, item in ipairs(entries) do
  local lines = await(function(cb)
    repository.patch(task, item, cb)
  end)
  local text = table.concat(lines, "\n")
  if item.kind == "staged" then
    assert(text:find("+staged", 1, true) and not text:find("+working", 1, true))
  end
  if item.kind == "unstaged" then
    assert(text:find("+working", 1, true) and not text:find("+staged", 1, true))
  end
  if item.kind == "untracked" then
    assert(text:find("+new", 1, true))
  end
end
local parsed = repository.parse_status("R  new\0old\0UU conflict\0", root)
assert(parsed[1].old_path == "old" and parsed[1].path == "new" and parsed[2].kind == "conflict")
-- Worktrees have a .git file, and their index lives in a separate git directory.
local worktree = root .. "-worktree"
run("worktree", "add", "-qb", "fixture-worktree", worktree)
local work = await(function(cb)
  git.discover(task, { cwd = worktree }, cb)
end)
assert(work.root == worktree and work.git_dir ~= worktree .. "/.git")
local called = false
local cancelled = git.task()
git.run(cancelled, root, { "status" }, function()
  called = true
end)
cancelled:close()
vim.wait(40, function()
  return false
end)
assert(not called, "Cancelled requests must not publish")
run("worktree", "remove", "--force", worktree)
vim.fn.delete(root, "rf")
print("git repository: status, literal paths, staged separation, worktrees and cancellation passed")
vim.cmd("qa!")
