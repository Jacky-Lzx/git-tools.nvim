vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api, diff = vim.api, require("git_tools.diff")
if not pcall(vim.treesitter.language.add, "markdown") then
  print("SKIP optional Markdown injection highlighting (parser not installed)")
  vim.cmd("qa!")
  return
end
local before = {
  "# Test",
  "",
  "<!-- toc:old -->",
  "- [Old](#old)",
  "<!-- toc:end -->",
  "",
  "```lua",
  "local n = 1",
  "return n",
  "```",
  "",
  "## test",
}
local after = vim.deepcopy(before)
after[3], after[4], after[8] = "<!-- toc:start -->", "- [Test](#test)", "local n = 2"
local patch, source = diff.unified(before, after, { old_path = "test.md", context = 0 })
local buffers = api.nvim_list_bufs()
local function render(sources)
  local buf = require("git_tools.diff.native").prepare(patch, {}, 100, sources)
  local rows = api.nvim_buf_get_lines(buf, 0, -1, false)
  local marks =
    api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsDiffSyntax"), 0, -1, { details = true })
  local counts = { html = 0, markdown_inline = 0, lua = 0 }
  for _, mark in ipairs(marks) do
    local text, hl = rows[mark[2] + 1], mark[4].hl_group
    if hl == "@comment.html" and text:match("^<!%-%-") then
      counts.html = counts.html + 1
      assert(mark[3] == 0 and mark[4].end_col == #text, "HTML ranges must use source bytes")
    elseif hl == "@markup.link.label.markdown_inline" and text:match("^%- %[") then
      counts.markdown_inline = counts.markdown_inline + 1
      assert(mark[3] == 3, "Inline capture must project within the Markdown list row")
    elseif hl == "@number.lua" and text:match("^local n =") then
      counts.lua = counts.lua + 1
      assert(mark[3] == #"local n = ")
    end
  end
  api.nvim_buf_delete(buf, { force = true })
  return counts
end
local counts = render({ source })
for lang, count in pairs(counts) do
  if pcall(vim.treesitter.language.add, lang) and vim.treesitter.query.get(lang, "highlights") then
    assert(count == 2, lang .. " must highlight both old and new source rows, got " .. count)
  end
end
-- Patch-only callers also retain injections when the snippet has enough context.
local full_patch = diff.unified({}, after, { old_path = "test.md" })
local buf = require("git_tools.diff.native").prepare(full_patch, {}, 100)
local groups = {}
for _, mark in
  ipairs(api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsDiffSyntax"), 0, -1, { details = true }))
do
  groups[mark[4].hl_group] = true
end
if pcall(vim.treesitter.language.add, "markdown_inline") then
  assert(groups["@markup.link.label.markdown_inline"], "Snippet fallback must parse inline injections too")
end
api.nvim_buf_delete(buf, { force = true })
assert(vim.deep_equal(buffers, api.nvim_list_bufs()), "Injected highlighting must not create source buffers")
print(
  "Markdown diff injections: inline links, HTML comments and fenced Lua on both sides, byte projection, snippet fallback and cleanup passed"
)
vim.cmd("qa!")
