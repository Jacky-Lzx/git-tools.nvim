vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api = vim.api
local diff, native = require("git_tools.diff"), require("git_tools.diff.native")
local ns, syntax_ns = api.nvim_create_namespace("GitToolsDiff"), api.nvim_create_namespace("GitToolsDiffSyntax")
local function lines(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end
local function marks(buf, namespace)
  return api.nvim_buf_get_extmarks(buf, namespace or ns, 0, -1, { details = true })
end
local opts = {
  layout = "top_bottom",
  highlights = function(document)
    local spans = {}
    for row, text in ipairs(document) do
      spans[#spans + 1] = { row = row - 1, col = 0, end_col = #text, hl_group = "TopBottomTest" }
    end
    return spans
  end,
}
local before = { "local unchanged = true", '\tlocal title = "旧名字🙂é"', "return title" }
local after =
  { "local unchanged = true", '\tlocal title = "新名字🚀é"', "local inserted = true", "return title" }
local patch, source = diff.unified(before, after, { old_path = "sample.lua" })
local buf = native.prepare(patch, opts, 80, { source })
local text = lines(buf)
assert(vim.b[buf].git_tools_diff_layout == "top_bottom" and not vim.bo[buf].modifiable)
assert(text[1] == "sample.lua" and text[2]:match("^Before  sample.lua"))
for index, line in ipairs(before) do
  assert(text[index + 2] == line, "The top block contains the entire old hunk")
end
local after_heading = 3 + #before
assert(text[after_heading]:match("^After  sample.lua"))
for index, line in ipairs(after) do
  assert(text[after_heading + index] == line, "The bottom block contains the entire new hunk")
end
assert(#text == #before + #after + 3, "Context appears independently on both sides")
local syntax, emphasis = {}, {}
for _, mark in ipairs(marks(buf, syntax_ns)) do
  local line = mark[2] + 1
  if mark[4].hl_group == "TopBottomTest" then
    syntax[line] = true
    assert(text[line]:sub(mark[3] + 1, mark[4].end_col) == text[line], "Syntax byte columns stay unchanged")
  end
end
for _, row in ipairs({ 3, 4, 5, 7, 8, 9, 10 }) do
  assert(syntax[row], "Full-document decorations color both changed and context rows")
end
for _, mark in ipairs(marks(buf)) do
  local row, detail = mark[2] + 1, mark[4]
  if (detail.hl_group or ""):match("Text$") then
    emphasis[detail.hl_group] = text[row]:sub(mark[3] + 1, detail.end_col)
  end
  if detail.virt_text and (row == 3 or row == 7) then
    local chunks = detail.virt_text
    assert(#chunks == 3 and chunks[1][1] == "1" and chunks[2][1] == " │ ", "Each side has its own single line number")
  end
end
assert(emphasis.GitToolsDiffDeleteText and emphasis.GitToolsDiffAddText)
if pcall(vim.treesitter.language.add, "lua") then
  local colored = {}
  for _, mark in ipairs(marks(buf, syntax_ns)) do
    if mark[4].hl_group:match("^@") then
      colored[mark[2] + 1] = true
    end
  end
  assert(colored[3] and colored[4] and colored[7] and colored[8], "Real syntax colors both blocks and context")
end

-- Reordering must preserve per-hunk and per-file boundaries, zero-count sides,
-- newline annotations and sparse source row projections.
local old = { "keep", "old first", "middle", "old second", "tail" }
local new = { "keep", "new first", "middle", "new second", "tail" }
local sparse_patch, sparse_source = diff.unified(old, new, { context = 0, old_path = "sparse.lua" })
local extra, extra_source = diff.unified("gone", "new", { old_path = "other.lua" })
vim.list_extend(sparse_patch, extra)
local sparse = native.prepare(sparse_patch, opts, 60, { sparse_source, extra_source })
local sparse_text = lines(sparse)
assert(sparse_text[3] == "old first" and sparse_text[5] == "new first")
assert(sparse_text[7] == "old second" and sparse_text[9] == "new second")
assert(sparse_text[10] == "other.lua" and sparse_text[12] == "gone" and sparse_text[15] == "new")
assert(sparse_text[13]:find("No newline", 1, true) and sparse_text[16]:find("No newline", 1, true))
local decorated = 0
for _, mark in ipairs(marks(sparse, syntax_ns)) do
  if mark[4].hl_group == "TopBottomTest" then
    decorated = decorated + 1
    assert(not sparse_text[mark[2] + 1]:match("^Before") and not sparse_text[mark[2] + 1]:match("^After"))
  end
end
assert(decorated == 6, "Sparse snapshots must not paint headings or omitted context")
for _, pair in ipairs({ { {}, { "added" } }, { { "deleted" }, {} } }) do
  local frame = native.prepare(diff.unified(pair[1], pair[2]), opts, 10)
  local values = lines(frame)
  assert(values[3] == (pair[1][1] or "(empty)") and values[5] == (pair[2][1] or "(empty)"))
  native.resize(frame, 2)
  assert(vim.deep_equal(values, lines(frame)), "Narrow previews retain full source text")
  api.nvim_buf_delete(frame, { force = true })
end
local compact = native.prepare(
  patch,
  { layout = "top_bottom", line_numbers = false, file_header = false, word_diff = false, syntax = false },
  30
)
assert(lines(compact)[1]:match("^Before") and not vim.tbl_contains(lines(compact), "sample.lua"))
assert(#marks(compact, syntax_ns) == 0)
for _, mark in ipairs(marks(compact)) do
  assert(not (mark[4].hl_group or ""):match("Text$"))
  if mark[4].virt_text then
    assert(#mark[4].virt_text == 1, "Disabled numbers leave only the change marker")
  end
end

-- Exercise publication, delta fallback and resize through the host contract.
local adopted, publications, cancelled = nil, 0, false
local win = api.nvim_get_current_win()
local ctx = {
  win = win,
  is_cancelled = function()
    return cancelled
  end,
  set_lines = function()
    error("Unexpected plain fallback")
  end,
  set_buffer = function(frame, metadata)
    assert(metadata.owned and metadata.backend == "native")
    adopted, publications = frame, publications + 1
    api.nvim_win_set_buf(win, frame)
    return true
  end,
}
local handle =
  diff.render(ctx, patch, { native = opts, backend = "delta", delta = { command = "/missing/git-tools-delta" } })
assert(vim.b[adopted].git_tools_diff_layout == "top_bottom")
api.nvim_win_set_cursor(win, { 8, 4 })
local view = vim.fn.winsaveview()
handle:resize()
assert(publications == 1 and vim.deep_equal(view, vim.fn.winsaveview()), "Resize retains the buffer, cursor and scroll")
local rules =
  api.nvim_buf_get_extmarks(adopted, api.nvim_create_namespace("GitToolsDiffBorders"), 0, -1, { details = true })
assert(#rules == 2 and #vim.b[adopted].git_tools_diff_hunks == 2)
handle:close()
assert(api.nvim_buf_is_valid(adopted), "The host owns adopted buffers")
cancelled = true
diff.render(ctx, patch, { native = opts })
assert(publications == 1)
local original = native.prepare(patch, {}, 60)
assert(vim.b[original].git_tools_diff_layout == "unified" and not lines(original)[2]:match("^Before"))
for _, frame in ipairs({ buf, sparse, compact, adopted, original }) do
  api.nvim_buf_delete(frame, { force = true })
end
print(
  "Top/bottom diff: hunk blocks, context, syntax, Unicode/tabs, sparse snapshots, newline markers, empty sides, resize and ownership passed"
)
vim.cmd("qa!")
