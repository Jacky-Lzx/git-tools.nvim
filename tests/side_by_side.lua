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
local function find(buf, left, right)
  for index, text in ipairs(lines(buf)) do
    if text:find(left, 1, true) and (not right or text:find(right, 1, true)) then
      return index, text
    end
  end
  error("Missing side-by-side row: " .. left .. " / " .. (right or ""))
end
local function check_width(buf, width)
  local sizes = {}
  for index, text in ipairs(lines(buf)) do
    sizes[index] = vim.fn.strdisplaywidth(text)
  end
  for _, mark in ipairs(marks(buf)) do
    for _, chunk in ipairs(mark[4].virt_text or {}) do
      sizes[mark[2] + 1] = sizes[mark[2] + 1] + vim.fn.strdisplaywidth(chunk[1])
    end
  end
  for _, size in ipairs(sizes) do
    assert(size <= width, "Code and virtual gutters must fit the host window")
  end
end
local before = { 'local title = "旧名字🙂"', "local count = 12", "return title, count" }
local after = { 'local title = "新名字🚀"', "local inserted = true", "local count = 34", "return title, count" }
local patch, source = diff.unified(before, after, { old_path = "sample.lua", ft = "lua" })
local opts = { layout = "side_by_side" }
local buf = native.prepare(patch, opts, 100, { source })
check_width(buf, 100)
assert(vim.b[buf].git_tools_diff_layout == "side_by_side" and not vim.bo[buf].modifiable)
assert(lines(buf)[1]:match("Before%s+│ After"))
local title, title_text = find(buf, before[1], after[1])
local count = find(buf, before[2], after[3])
local inserted, inserted_text = find(buf, after[2])
assert(not inserted_text:find("local count", 1, true) and title < inserted and inserted < count)
local context = find(buf, before[3], after[4])
assert(select(2, lines(buf)[context]:gsub("return title, count", "")) == 2, "Context appears on both sides")
local backgrounds, emphasis, gutters = 0, {}, {}
for _, mark in ipairs(marks(buf)) do
  local detail = mark[4]
  local group = detail.hl_group or ""
  if group == "GitToolsDiffAdd" or group == "GitToolsDiffDelete" then
    backgrounds = backgrounds + 1
    assert(not detail.hl_eol, "Backgrounds cannot spill across the other column")
  elseif group:match("Text$") and mark[2] + 1 == title then
    emphasis[group] = title_text:sub(mark[3] + 1, detail.end_col)
  end
  if detail.virt_text and mark[2] + 1 == title then
    gutters[#gutters + 1] = table.concat(vim.tbl_map(function(chunk)
      return chunk[1]
    end, detail.virt_text))
  end
end
assert(backgrounds == 5 and #gutters == 2)
assert(gutters[1] == "1 - " and gutters[2] == " │ 1 + ")
assert(emphasis.GitToolsDiffDeleteText and emphasis.GitToolsDiffAddText)

-- Full-document decoration spans must project onto both columns, including
-- context, with source bytes preserved across tabs, Unicode and clipping.
local decorated = {
  layout = "side_by_side",
  highlights = function(document)
    local spans = {}
    for index, text in ipairs(document) do
      spans[#spans + 1] = { row = index - 1, col = 0, end_col = #text, hl_group = "SideTest" }
    end
    return spans
  end,
}
local painted = native.prepare(patch, decorated, 100, { source })
local context_marks = 0
for _, mark in ipairs(marks(painted, syntax_ns)) do
  if mark[2] + 1 == context and mark[4].hl_group == "SideTest" then
    context_marks = context_marks + 1
    assert(lines(painted)[context]:sub(mark[3] + 1, mark[4].end_col) == before[3])
  end
end
assert(context_marks == 2, "Full snapshots must color context on both sides")
if pcall(vim.treesitter.language.add, "lua") then
  local sides = { left = false, right = false }
  for _, mark in ipairs(marks(painted, syntax_ns)) do
    if mark[2] + 1 == title and mark[4].hl_group:match("^@") then
      sides[mark[3] == 0 and "left" or mark[3] > #title_text / 2 and "right" or "left"] = true
    end
  end
  assert(sides.left and sides.right, "Installed parsers color both columns")
end
local tab_patch, tab_source = diff.unified(
  { "\t旧🙂é value = 12" },
  { "\t新🚀é value = 34" },
  { old_path = "tabs.lua" }
)
local tabs = native.prepare(tab_patch, decorated, 80, { tab_source })
local tab_row, tab_text = find(tabs, "旧🙂é", "新🚀é")
assert(not tab_text:find("\t", 1, true), "Tabs must expand independently in each column")
local decorated_text = {}
for _, mark in ipairs(marks(tabs, syntax_ns)) do
  if mark[4].hl_group == "SideTest" then
    decorated_text[#decorated_text + 1] = lines(tabs)[mark[2] + 1]:sub(mark[3] + 1, mark[4].end_col)
  end
end
assert(#decorated_text == 2 and decorated_text[1]:match("^        "))
assert(decorated_text[1]:find("旧🙂é", 1, true) and decorated_text[2]:find("新🚀é", 1, true))
native.resize(tabs, 28)
check_width(tabs, 28)
for _, text in ipairs(lines(tabs)) do
  assert(vim.fn.strdisplaywidth(text) <= 28)
  assert(vim.str_utfindex(text) >= 0, "Clipping must not split UTF-8")
end
local clipped = false
for _, mark in ipairs(marks(tabs, syntax_ns)) do
  local text = lines(tabs)[mark[2] + 1]:sub(mark[3] + 1, mark[4].end_col)
  assert(not text:find("…", 1, true), "Syntax must not color clipping markers")
  clipped = true
end
assert(clipped)
native.resize(tabs, 80)
assert(find(tabs, "旧🙂é", "新🚀é") == tab_row, "Widening must restore original text")

-- Render through the public API, resize the same adopted frame, and retain
-- cursor/topline. Shrinking below a useful column width uses unified text.
local adopted, publications = nil, 0
local win = api.nvim_get_current_win()
local handle = diff.render({
  win = win,
  is_cancelled = function()
    return false
  end,
  set_lines = function()
    error("Unexpected plain fallback")
  end,
  set_buffer = function(frame)
    adopted, publications = frame, publications + 1
    api.nvim_win_set_buf(win, frame)
    return true
  end,
}, patch, { native = opts, sources = { source } })
api.nvim_win_set_cursor(win, { title, 5 })
local saved = vim.fn.winsaveview()
native.resize(adopted, 60)
assert(api.nvim_win_get_cursor(win)[1] == title and vim.fn.winsaveview().topline == saved.topline)
assert(publications == 1 and not vim.bo[adopted].modifiable)
native.resize(adopted, 10)
assert(vim.tbl_contains(lines(adopted), before[1]) and vim.tbl_contains(lines(adopted), after[1]))
native.resize(adopted, 100)
find(adopted, before[1], after[1])
handle:close()
assert(api.nvim_buf_is_valid(adopted), "The host still owns the adopted frame")

-- A missing delta must preserve the requested native layout on fallback.
local fallback
local fallback_handle = diff.render({
  win = win,
  is_cancelled = function()
    return false
  end,
  set_lines = function()
    error("Unexpected plain fallback")
  end,
  set_buffer = function(frame)
    fallback = frame
    return true
  end,
}, patch, { backend = "delta", native = opts, delta = { command = "/missing/git-tools-delta" } })
assert(vim.b[fallback].git_tools_diff_layout == "side_by_side")
fallback_handle:close()
api.nvim_buf_delete(fallback, { force = true })

for _, pair in ipairs({ { {}, { "added" } }, { { "deleted" }, {} } }) do
  local frame = native.prepare(diff.unified(pair[1], pair[2]), opts, 60)
  local row = find(frame, pair[1][1] or pair[2][1])
  local columns = {}
  for _, mark in ipairs(marks(frame)) do
    if mark[2] + 1 == row and mark[4].virt_text then
      columns[#columns + 1] = mark[3]
    end
  end
  assert(#columns == 2 and columns[1] == 0 and columns[2] > 0)
  api.nvim_buf_delete(frame, { force = true })
end
local disabled =
  native.prepare(patch, { layout = "side_by_side", word_diff = false, line_numbers = false, file_header = false }, 100)
find(disabled, before[2], after[3])
for _, mark in ipairs(marks(disabled)) do
  assert(not (mark[4].hl_group or ""):match("Text$"))
  for _, chunk in ipairs(mark[4].virt_text or {}) do
    assert(not chunk[1]:match("%d"), "line_numbers=false removes both number gutters")
  end
end
assert(not vim.tbl_contains(lines(disabled), "sample.lua"))
local multiple = vim.list_slice(patch)
local extra = diff.unified("gone", "new", { old_path = "other.txt" })
vim.list_extend(multiple, extra)
local multi = native.prepare(multiple, opts, 60)
find(multi, "gone", "new")
find(multi, "No newline")
assert(vim.tbl_contains(lines(multi), "other.txt"), "File sections must remain separate")
local original = native.prepare(patch, {}, 100)
assert(
  vim.tbl_contains(lines(original), before[1]) and not lines(original)[1]:find("Before", 1, true),
  "Default stays unified"
)
for _, frame in ipairs({ buf, painted, tabs, adopted, disabled, multi, original }) do
  api.nvim_buf_delete(frame, { force = true })
end
print(
  "Side-by-side diff: alignment, syntax, Unicode/tabs, clipping, gutters, resize, narrow fallback, ownership and default passed"
)
vim.cmd("qa!")
