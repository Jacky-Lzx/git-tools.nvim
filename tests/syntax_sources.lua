vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api = vim.api
local diff, model, native = require("git_tools.diff"), require("git_tools.diff.model"), require("git_tools.diff.native")
local before = {
  "local function outer(value)",
  "  local items = {",
  "    { value },",
  "  }",
  "  --[[",
  "  long comment",
  "  ]]",
  "  return items",
  "end",
}
local after = vim.deepcopy(before)
after[1] = "local function outer(value, extra)"
after[6] = "  changed comment 中文😀"
after[9] = "end -- changed"
local patch, source = diff.unified(before, after, { old_path = "sample.lua", context = 0 })
local buffers = api.nvim_list_bufs()
local parsed = model.parse(patch, { file_header = false }, { source })
assert(#parsed.documents == 2, "Full snapshots must be parsed once per side across all hunks")
assert(vim.deep_equal(parsed.documents[1].lines, before) and vim.deep_equal(parsed.documents[2].lines, after))
for _, doc in ipairs(parsed.documents) do
  assert(doc.full and doc.rows[6] and doc.rows[9], "Sparse source rows must include separated hunks")
  for line, row in pairs(doc.rows) do
    assert(parsed.rows[row].text == doc.lines[line], "Projection must target exact source text")
  end
end
local malformed = vim.deepcopy(source)
malformed.before[6] = "wrong snapshot"
local fallback = model.parse(patch, {}, { malformed })
assert(not fallback.documents[1].full, "Stale side must fall back without coloring from wrong contents")
local bare = model.parse(patch)
assert(not bare.documents[1].full and #bare.documents > 2, "Patch-only callers retain snippets")
-- Source arrays are captured, not aliased to a caller's editable lines.
before[1] = "mutated outside"
assert(source.before[1] ~= before[1])

if pcall(vim.treesitter.language.add, "lua") then
  vim.treesitter.query.set(
    "lua",
    "highlights",
    [[
    (function_declaration ["function" "end"] @keyword.function)
    (comment) @comment
    (identifier) @variable
    ["(" ")" "{" "}"] @punctuation.bracket
  ]]
  )
  local buf = native.prepare(patch, {}, 90, { source })
  local rows = api.nvim_buf_get_lines(buf, 0, -1, false)
  local marks =
    api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsDiffSyntax"), 0, -1, { details = true })
  local ending, comment = 0, 0
  for _, mark in ipairs(marks) do
    local text, hl = rows[mark[2] + 1], mark[4].hl_group
    if text:match("^end") and hl == "@keyword.function.lua" then
      ending = ending + 1
    end
    if text:find("comment", 1, true) and hl == "@comment.lua" then
      comment = comment + 1
    end
  end
  assert(ending == 2 and comment == 2, "Function ends and long comments must use full context on BOTH sides")
  api.nvim_buf_delete(buf, { force = true })
else
  print("SKIP optional installed Lua parser capture test")
end

-- Generic decorations are projected only on their side, at byte coordinates.
local calls = 0
local buf = native.prepare(patch, {
  highlights = function(lines, ft)
    calls = calls + 1
    assert(ft == "lua")
    return { { row = 5, col = 2, end_col = 6, hl_group = "TestDecoration", priority = 999 } }
  end,
}, 70, { source })
local marks = api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsDiffSyntax"), 0, -1, { details = true })
local decorations = 0
for _, mark in ipairs(marks) do
  if mark[4].hl_group == "TestDecoration" then
    decorations = decorations + 1
    assert(mark[4].priority == 149 and mark[3] == 2)
  end
end
assert(calls == 2 and decorations == 2)
api.nvim_buf_delete(buf, { force = true })
assert(vim.deep_equal(buffers, api.nvim_list_bufs()), "Highlighting leaks no source or scratch buffers")
assert(not package.loaded["pairs"] and not package.loaded["pairs.rainbow"], "Preview never eagerly loads pairs")
print(
  "Full diff syntax: sparse multi-hunk mapping, old/new context, stale fallback, Unicode, decorations and isolation passed"
)
vim.cmd("qa!")
