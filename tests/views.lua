vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api, tools = vim.api, require("git_tools")
vim.o.columns = 160
vim.o.lines = 45
vim.o.hidden = true
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local function command(...)
  local args = { "git", "-C", root, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null" }
  vim.list_extend(args, { ... })
  return vim.system(args):wait()
end
local function git(...)
  local result = command(...)
  assert(result.code == 0, result.stderr)
  return result.stdout
end
git("init", "-qb", "main")
git("config", "user.name", "Fixture")
git("config", "user.email", "fixture@example.invalid")
vim.fn.writefile({ "base" }, root .. "/a.txt")
vim.fn.writefile({ "other" }, root .. "/b.txt")
git("add", ".")
git("commit", "-qm", "initial")
local initial = git("rev-parse", "HEAD"):gsub("\n$", "")
vim.fn.writefile({ "index" }, root .. "/a.txt")
git("add", "a.txt")
vim.fn.writefile({ "disk" }, root .. "/a.txt")
local function wait(test, message)
  assert(vim.wait(5000, test, 5), message or "View timeout")
end
local function text(win)
  return table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false), "\n")
end
local view = tools.compare({ cwd = root })
wait(function()
  return view.current ~= nil
end)
assert(view.current.kind == "staged" and text(view.windows[1]) == "base" and text(view.windows[2]) == "index")
view:select(2)
wait(function()
  return view.current.kind == "unstaged"
end)
assert(text(view.windows[1]) == "index" and text(view.windows[2]) == "disk")
assert(vim.wo[view.windows[1]].diff and vim.wo[view.windows[2]].diff)
local actual = view.result
api.nvim_buf_set_lines(actual, 0, -1, false, { "unsaved" })
view:close()
assert(api.nvim_buf_is_valid(actual) and vim.bo[actual].modified, "Closing diff must preserve unsaved file buffer")
assert(vim.fn.maparg("q", "n", false, true).buffer ~= 1, "View mappings must be released")
view = tools.compare({ cwd = root, commit = initial })
wait(function()
  return view.current ~= nil
end)
assert(text(view.windows[1]) == "" and text(view.windows[2]) == "base", "Root commit uses an empty left side")
view:close()
git("add", "a.txt")
git("commit", "-qm", "changed")
view = tools.compare({ cwd = root, from = initial, to = "HEAD" })
wait(function()
  return view.current ~= nil
end)
assert(
  text(view.windows[1]) == "base" and text(view.windows[2]) == "disk",
  "Revision comparison must ignore unsaved buffer"
)
view:close()
api.nvim_buf_delete(actual, { force = true })
git("reset", "--hard", initial)
git("checkout", "-qb", "side")
vim.fn.writefile({ "theirs" }, root .. "/a.txt")
git("add", "a.txt")
git("commit", "-qm", "side")
git("checkout", "-q", "main")
vim.fn.writefile({ "ours" }, root .. "/a.txt")
git("add", "a.txt")
git("commit", "-qm", "main")
assert(command("-c", "merge.conflictstyle=diff3", "merge", "side").code ~= 0)
view = tools.merge({ cwd = root })
wait(function()
  return view.current ~= nil
end)
assert(#view.windows == 3 and text(view.windows[1]) == "ours" and text(view.windows[3]) == "theirs")
local conflict = require("git_tools.conflict")
assert(#conflict.blocks(api.nvim_buf_get_lines(view.result, 0, -1, false)) == 1)
local rejected
view:resolve(function(err)
  rejected = err
end)
assert(rejected and git("ls-files", "-u") ~= "", "Unresolved markers must block staging")
api.nvim_set_current_win(view.windows[2])
api.nvim_win_set_cursor(0, { 1, 0 })
assert(conflict.choose("both", view.result))
assert(text(view.windows[2]) == "ours\ntheirs")
assert(git("ls-files", "-u") ~= "", "Choosing text must not stage implicitly")
local done
view:resolve(function(err)
  assert(not err, err)
  done = true
end)
wait(function()
  return done
end)
assert(git("ls-files", "-u") == "" and git("show", ":a.txt") == "ours\ntheirs\n")
view:close()
vim.fn.delete(root, "rf")
print(
  "git views: multi-file staged/working and revision diffs, root commits, unsaved preservation and real three-way conflict resolution passed"
)
vim.cmd("qa!")
