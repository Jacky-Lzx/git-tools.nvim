vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
vim.opt.rtp:prepend(assert(vim.env.SELECTION_TOOLS_DIR))
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function git(...)
  local result = vim.system(vim.list_extend({ "git", "-C", root }, { ... })):wait()
  assert(result.code == 0, result.stderr)
end
git("init", "-q")
vim.fn.writefile({ "old" }, root .. "/sample.txt")
git("add", ".")
git(
  "-c",
  "user.name=Fixture",
  "-c",
  "user.email=fixture@example.invalid",
  "-c",
  "commit.gpgsign=false",
  "-c",
  "core.hooksPath=/dev/null",
  "commit",
  "-qm",
  "initial"
)
vim.fn.writefile({ "new" }, root .. "/sample.txt")
local api = vim.api
local p = require("git_tools").status({ cwd = root })
assert(
  vim.wait(5000, function()
    return p:current() ~= nil
      and table
          .concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(p.preview_win), 0, -1, false), "\n")
          :find("+new", 1, true)
        ~= nil
  end, 5),
  "Status picker must load real Git results and patch"
)
p:set_query("no-match")
assert(vim.wait(1000, function()
  return p:current() == nil
end, 5))
p:set_query("sample")
assert(vim.wait(1000, function()
  return p:current() ~= nil
end, 5))
p.opts.actions.stage(p)
assert(
  vim.wait(5000, function()
    local item = p:current()
    return item and item.kind == "staged"
  end, 5),
  "Stage must refresh the same picker"
)
p.opts.actions.unstage(p)
assert(
  vim.wait(5000, function()
    local item = p:current()
    return item and item.kind == "unstaged"
  end, 5),
  "Unstage must refresh the same picker"
)
assert(p.query == "sample", "Actions must preserve the filter")
p.opts.actions.group(p)
assert(
  vim.wait(5000, function()
    local item = p:current()
    return item and item.hunk ~= nil
  end, 5),
  "F4 must switch to hunk results"
)
assert(p.query == "sample")
local source = vim.fn.bufadd(root .. "/sample.txt")
vim.fn.bufload(source)
api.nvim_buf_set_lines(source, 0, 0, false, { "unsaved prefix" })
p:confirm()
assert(vim.wait(1000, function()
  return vim.api.nvim_buf_get_name(0):match("sample.txt$") ~= nil
end, 5))
assert(api.nvim_win_get_cursor(0)[1] == 2, "Hunk jump must account for unsaved inserted lines")
local log = require("git_tools").log({ cwd = root })
assert(vim.wait(5000, function()
  return log:current() ~= nil
end, 5))
assert(log:current().subject == "initial")
log:confirm()
assert(vim.wait(5000, function()
  return vim.api.nvim_buf_get_name(0):find("git-tools://", 1, true) ~= nil
end, 5))
assert(not vim.bo.modifiable and vim.bo.filetype == "diff")
vim.cmd("tabclose")
vim.fn.delete(root, "rf")
print("git workflows: real status picker, filtering, preview and file confirmation passed")
vim.cmd("qa!")
