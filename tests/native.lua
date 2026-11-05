vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api = vim.api
local diff = require("git_tools.diff")
local model = require("git_tools.diff.model")
local words = require("git_tools.diff.words")
local native = require("git_tools.diff.native")
local patch = diff.unified(
  { 'local title = "旧名字"', "local count = 12", "return title, count" },
  { 'local title = "新名字"', "local inserted = true", "local count = 34", "return title, count" },
  { old_path = "file:///tmp/中文.lua" }
)
local parsed = model.parse(patch)
assert(parsed.rows[1].text == "/tmp/中文.lua")
assert(parsed.rows[2].kind == "hunk" and parsed.rows[2].text:find(":1", 1, true))
local old_title, new_title, inserted, new_count
for _, row in ipairs(parsed.rows) do
  if row.kind == "delete" and row.old == 1 then
    old_title = row
  elseif row.kind == "add" and row.new == 1 then
    new_title = row
  elseif row.kind == "add" and row.new == 2 then
    inserted = row
  elseif row.kind == "add" and row.new == 3 then
    new_count = row
  end
end
assert(old_title.text:sub(old_title.emphasis[1][1] + 1, old_title.emphasis[1][2]) == "旧")
assert(new_title.text:sub(new_title.emphasis[1][1] + 1, new_title.emphasis[1][2]) == "新")
assert(not inserted.emphasis, "An inserted line must not shift all subsequent replacement pairs")
assert(new_count.text:sub(new_count.emphasis[1][1] + 1, new_count.emphasis[1][2]) == "34")
local a, b = words.ranges("a中x🙂b", "a文x🚀b")
assert(#a == 2 and #b == 2, "Separate Unicode changes need separate emphasis spans")
assert(a[1][1] == 1 and a[1][2] == 4 and a[2][1] == 5 and a[2][2] == 9)

-- Single-line replacements must not depend on shared identifier tokens.
for _, pair in ipairs({
  { '    auto("table(%d+)x(%d+)%s", {', "    auto(line_begin, {" },
  { "    }, line_begin),", '    }, "table(%d+)x(%d+)%s"),' },
  { "  old_name()", "  new_name()" },
  { "  }),", "  });" },
  { "  旧()", "  新()" },
}) do
  local replacement = diff.unified({ pair[1] }, { pair[2] }, { old_path = "single.lua" })
  local rows = model.parse(replacement).rows
  local left, right = words.ranges(pair[1], pair[2])
  assert(#left > 0 and #right > 0)
  assert(
    vim.deep_equal(rows[3].emphasis, left) and vim.deep_equal(rows[4].emphasis, right),
    "Single replacements need character emphasis even without token overlap"
  )
  local frame = native.prepare(replacement, { syntax = false }, 80)
  local highlighted = { delete = {}, add = {} }
  for _, mark in
    ipairs(api.nvim_buf_get_extmarks(frame, api.nvim_create_namespace("GitToolsDiff"), 0, -1, { details = true }))
  do
    local detail = mark[4]
    local side = detail.hl_group == "GitToolsDiffDeleteText" and "delete"
      or detail.hl_group == "GitToolsDiffAddText" and "add"
    if side then
      table.insert(highlighted[side], { mark[3], detail.end_col })
    end
  end
  assert(
    vim.deep_equal(highlighted.delete, left) and vim.deep_equal(highlighted.add, right),
    "Native frames must paint both sides of a single replacement"
  )
  api.nvim_buf_delete(frame, { force = true })
  local disabled = model.parse(replacement, { word_diff = false }).rows
  assert(not disabled[3].emphasis and not disabled[4].emphasis, "word_diff=false must suppress emphasis")
end
for _, pair in ipairs({ { {}, { "inserted" } }, { { "deleted" }, {} } }) do
  local rows = model.parse(diff.unified(pair[1], pair[2])).rows
  for _, row in ipairs(rows) do
    assert(not row.emphasis, "Pure insertion/deletion must retain line-only highlights")
  end
end
local oversized = { { text = string.rep("a", 4097) } }
words.align(oversized, { { text = "b" } })
assert(vim.deep_equal(oversized[1].emphasis, {}), "Single replacements must retain the character diff limit")

local special = model.parse({
  'diff --git "a/\\344\\270\\255.lua" "b/\\344\\270\\255.lua"',
  "index 123..456 100644",
  '--- "a/\\344\\270\\255.lua"',
  '+++ "b/\\344\\270\\255.lua"',
  "@@ -1 +1 @@",
  "--- looks like a header",
  "+++ also code",
  "\\ No newline at end of file",
  "diff --git a/empty.lua b/empty.lua",
  "new file mode 100644",
  "--- /dev/null",
  "+++ b/empty.lua",
  "@@ -0,0 +1 @@",
  "+return true",
})
assert(special.rows[1].text == "中.lua")
assert(special.rows[3].kind == "delete" and special.rows[3].text == "-- looks like a header")
assert(special.rows[4].kind == "add" and special.rows[4].text == "++ also code")
assert(special.rows[5].text:find("No newline", 1, true))
assert(special.rows[#special.rows].new == 1 and not special.rows[#special.rows].old)
local compact = model.parse(patch, { file_header = false })
assert(compact.rows[1].kind == "hunk" and compact.documents[1].rows[1] == 2)
local removed = model.parse({ "--- a/gone.lua", "+++ /dev/null", "@@ -9 +0,0 @@", "-return 9" })
assert(removed.rows[2].text:find("gone.lua:9", 1, true) and removed.rows[3].old == 9)
assert(removed.documents[2].path == "gone.lua")

local buf = native.prepare(patch, {}, 70)
assert(vim.bo[buf].buftype == "nofile" and not vim.bo[buf].modifiable)
local text = api.nvim_buf_get_lines(buf, 0, -1, false)
assert(vim.tbl_contains(text, 'local title = "新名字"'), "Copied code must not include gutter decorations")
local marks = api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsDiff"), 0, -1, { details = true })
local gutter, backgrounds, emphasis = 0, 0, 0
for _, mark in ipairs(marks) do
  local detail = mark[4]
  if detail.virt_text then
    gutter = gutter + 1
    assert(detail.virt_text_pos == "inline")
  end
  if detail.hl_eol then
    backgrounds = backgrounds + 1
  end
  if (detail.hl_group or ""):find("Text$") then
    emphasis = emphasis + 1
  end
end
assert(gutter == #text - 2 and backgrounds == 5 and emphasis >= 4)
local syntax =
  api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsDiffSyntax"), 0, -1, { details = true })
local sides = {}
for _, mark in ipairs(syntax) do
  sides[text[mark[2] + 1]] = true
end
-- Exercise a real installed parser, while keeping this optional dependency optional.
if pcall(vim.treesitter.language.add, "lua") then
  assert(#syntax > 0, "Installed Lua parser must color old and new snippets")
  assert(sides['local title = "旧名字"'] and sides['local title = "新名字"'])
else
  print("SKIP optional Lua Tree-sitter coloring (parser not installed)")
end
native.resize(buf, 20)
local borders =
  api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsDiffBorders"), 0, -1, { details = true })
assert(vim.fn.strdisplaywidth(borders[1][4].virt_lines[1][1][1]) == 20)
local unknown = native.prepare(diff.unified("a\n", "b\n", { old_path = "x.unknown-language" }), {}, 10)
assert(vim.b[unknown].git_tools_diff, "Missing language parsers must leave a usable diff")

local adopted, cancelled, publications = nil, false, 0
local ctx = {
  win = api.nvim_get_current_win(),
  is_cancelled = function()
    return cancelled
  end,
  set_lines = function()
    error("Unexpected fallback")
  end,
  set_buffer = function(frame, metadata)
    assert(metadata.owned)
    publications = publications + 1
    adopted = frame
    return true
  end,
}
local system = vim.system
vim.system = function()
  error("Native rendering must not spawn a process")
end
local handle = diff.render(ctx, patch)
assert(vim.b[adopted].git_tools_diff, "Native is the default backend")
api.nvim_win_set_buf(ctx.win, adopted)
api.nvim_win_set_cursor(ctx.win, { 3, 2 })
handle:resize()
assert(
  publications == 1 and api.nvim_win_get_cursor(ctx.win)[1] == 3,
  "Resize preserves the ready frame and scroll position"
)
handle:close()
assert(api.nvim_buf_is_valid(adopted), "The host owns adopted buffers after renderer close")
cancelled = true
diff.render(ctx, patch)
assert(publications == 1)
cancelled = false
local rejected, fallback
ctx.set_buffer = function(frame)
  rejected = frame
  return false
end
ctx.set_lines = function(lines)
  fallback = lines
end
diff.render(ctx, patch)
assert(not api.nvim_buf_is_valid(rejected) and vim.deep_equal(fallback, patch), "Rejected frames are released")
vim.system = system

local large = { "--- large.txt", "+++ large.txt", "@@ -0,0 +1,12000 @@" }
for _ = 1, 12000 do
  large[#large + 1] = "+some code"
end
local limited, truncated = native.prepare(large, { syntax = false }, 40)
assert(truncated and api.nvim_buf_line_count(limited) <= 10001)
assert(api.nvim_buf_get_lines(limited, -2, -1, false)[1]:find("truncated", 1, true))
print(
  "Native diff: Unicode spans, line alignment, paths, zero-count hunks, real syntax, virtual gutters, resize, cancellation and limits passed"
)
vim.cmd("qa!")
