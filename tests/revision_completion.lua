local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
vim.o.wildoptions = ""
local api = vim.api
local git = require("git_tools.git")
local plugin = require("git_tools")
local fixture = dofile(root .. "/tests/helpers.lua").fixture
local first, second = fixture(), fixture()
for _, repo in ipairs({ first, second }) do
  repo:write("sample.txt", { "one" })
  repo:git("add", ".")
  repo:git("commit", "-qm", "initial")
end
first:git("branch", "feature/rework")
first:git("branch", "release")
first:git("tag", "-am", "Release", "v1.0")
first:git("tag", "release")
first:git("config", "core.warnAmbiguousRefs", "false")
first:git("update-ref", "refs/remotes/origin/main", "HEAD")
first:git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
second:git("branch", "second-only")

plugin.setup({ buffer = false })
local function complete(line)
  return vim.fn.getcompletion("GitTools " .. line, "cmdline", true)
end
local read, reads = git.read, 0
git.read = function(...)
  reads = reads + 1
  return read(...)
end

api.nvim_set_current_dir(second.root)
vim.cmd.edit(first.root .. "/sample.txt")
local refs = complete("compare ")
assert(
  vim.deep_equal(refs, {
    "HEAD",
    "HEAD~1",
    "feature/rework",
    "main",
    "heads/release",
    "origin/main",
    "tags/release",
    "v1.0",
  }),
  vim.inspect(refs)
)
assert(reads == 2, "A cold lookup should resolve the repository and read its refs")
assert(vim.deep_equal(complete("compare feature/r"), { "feature/rework" }))
assert(vim.deep_equal(complete("compare HEAD~1 origin/ma"), { "origin/main" }))
assert(vim.deep_equal(complete("log v1"), { "v1.0" }))
vim.o.wildoptions = "fuzzy"
assert(vim.deep_equal(complete("compare frrk"), { "feature/rework" }))
vim.o.wildoptions = ""
assert(reads == 2, "Matching cached refs must not start Git again")

vim.fn.mkdir(first.root .. "/nested")
vim.cmd.edit(first.root .. "/nested/new.txt")
assert(vim.deep_equal(complete("compare feature/"), { "feature/rework" }))
assert(reads == 3, "A new directory in the same repository should reuse its refs")
api.nvim_set_current_buf(api.nvim_create_buf(false, true))
assert(vim.deep_equal(complete("compare second"), { "second-only" }))
assert(#complete("compare feature/") == 0, "A special buffer should use the active working directory")

vim.cmd.edit(first.root .. "/sample.txt")
first:git("branch", "refreshed")
local clock = vim.uv.hrtime
vim.uv.hrtime = function()
  return clock() + 3e9
end
assert(
  vim.wait(5000, function()
    return vim.deep_equal(complete("compare refres"), { "refreshed" })
  end, 10),
  "Expired refs should refresh in the background"
)
vim.uv.hrtime = clock

require("git_tools.revisions").dispose()
local counted_read = git.read
git.read = function(cwd, args, timeout)
  if vim.tbl_contains(args, "for-each-ref") then
    return nil, 124
  end
  return counted_read(cwd, args, timeout)
end
assert(vim.deep_equal(complete("compare "), { "HEAD", "HEAD~1" }))
assert(
  vim.wait(5000, function()
    return vim.deep_equal(complete("compare feature/"), { "feature/rework" })
  end, 10),
  "Refs that time out during the first lookup should load in the background"
)
git.read = counted_read

local outside = vim.fn.tempname()
vim.fn.mkdir(outside)
api.nvim_set_current_dir(outside)
api.nvim_set_current_buf(api.nvim_create_buf(false, true))
assert(vim.deep_equal(complete("compare "), { "HEAD", "HEAD~1" }))
local failed_reads = reads
assert(#complete("compare ma") == 0 and reads == failed_reads, "Cache failed repository lookups")
git.read = read
plugin._dispose()
api.nvim_set_current_dir(root)
first:cleanup()
second:cleanup()
vim.fn.delete(outside, "rf")
print("Revision completion: refs, matching, repository context, caching and fallback passed")
