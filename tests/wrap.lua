vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api = vim.api
local diff, native = require("git_tools.diff"), require("git_tools.diff.native")
local window = require("git_tools.diff.window")
local before = 'local text = "' .. string.rep("旧é🙂", 12) .. '\tEND_OLD"'
local after = 'local text = "' .. string.rep("新é🚀", 12) .. '\tEND_NEW"'
local patch, source = diff.unified({ before }, { after }, { old_path = "wrap.lua", ft = "lua" })
local ns = api.nvim_create_namespace("GitToolsDiff")
local syntax_ns = api.nvim_create_namespace("GitToolsDiffSyntax")
local function toggle(buf, mode)
  local mapping = api.nvim_buf_call(buf, function()
    return vim.fn.maparg("<M-z>", mode or "n", false, true)
  end)
  assert(type(mapping.callback) == "function", "Alt+Z must have a local mapping")
  mapping.callback()
  return mapping.callback
end
local function reconstruct(buf, width)
  local texts = api.nvim_buf_get_lines(buf, 0, -1, false)
  local by_row, left, right = {}, {}, {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    if mark[4].virt_text then
      by_row[mark[2] + 1] = by_row[mark[2] + 1] or {}
      table.insert(by_row[mark[2] + 1], mark)
    end
  end
  for row, text in ipairs(texts) do
    local size = vim.fn.strdisplaywidth(text)
    local marks = by_row[row]
    if marks then
      table.sort(marks, function(a, b)
        return a[3] < b[3]
      end)
      assert(#marks == 2)
      left[#left + 1] = text:sub(1, marks[2][3]):gsub(" +$", "")
      right[#right + 1] = text:sub(marks[2][3] + 1):gsub(" +$", "")
      for _, mark in ipairs(marks) do
        for _, chunk in ipairs(mark[4].virt_text) do
          size = size + vim.fn.strdisplaywidth(chunk[1])
        end
      end
    end
    assert(size <= width, "Wrapped Unicode and gutters must fit the host")
  end
  -- Padding is omitted here; spaces inside the original code are retained by
  -- comparing non-space bytes, while a separate ASCII case checks exact text.
  return table.concat(left):gsub(" +", ""), table.concat(right):gsub(" +", "")
end
for _, numbers in ipairs({ true, false }) do
  local buf = native.prepare(patch, {
    layout = "side_by_side",
    wrap = true,
    line_numbers = numbers,
    highlights = function(lines)
      return { { row = 0, col = 0, end_col = #lines[1], hl_group = "TestWrapSpan" } }
    end,
  }, 44, { source })
  for _, width in ipairs({ 44, 30, 18, 70 }) do
    native.resize(buf, width)
    local left, right = reconstruct(buf, width)
    assert(
      left == before:gsub("[ \t]", "") and right == after:gsub("[ \t]", ""),
      "Wrapping must retain every code byte"
    )
  end
  local decorated, emphasized = {}, {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, syntax_ns, 0, -1, { details = true })) do
    if mark[4].hl_group == "TestWrapSpan" then
      decorated[mark[2]] = true
    end
  end
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    if (mark[4].hl_group or ""):match("Text$") then
      emphasized[mark[2]] = true
    end
  end
  assert(
    vim.tbl_count(decorated) > 2 and vim.tbl_count(emphasized) > 2,
    "Continuation rows retain decorations and emphasis"
  )
  native.resize(buf, 10)
  assert(
    table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("END_NEW", 1, true),
    "Narrow fallback retains full lines"
  )
  native.resize(buf, 44)
  native.set_wrap(buf, false, 44)
  assert(table.concat(api.nvim_buf_get_lines(buf, 0, -1, false)):find("…", 1, true))
  native.set_wrap(buf, true, 44)
  local left, right = reconstruct(buf, 44)
  assert(left:find("END_OLD", 1, true) and right:find("END_NEW", 1, true))
  api.nvim_buf_delete(buf, { force = true })
end

local win, original = api.nvim_get_current_win(), api.nvim_get_current_buf()
local previous_wrap = vim.wo[win].wrap
local ctx = {
  win = win,
  is_cancelled = function()
    return false
  end,
}
ctx.set_buffer = function(buf)
  api.nvim_win_set_buf(win, buf)
  return true
end
ctx.set_lines = function(lines)
  api.nvim_win_set_buf(win, original)
  api.nvim_buf_set_lines(original, 0, -1, false, lines)
end
for _, layout in ipairs({ "unified", "top_bottom", "side_by_side" }) do
  local handle = diff.render(ctx, patch, { wrap = true, native = { layout = layout }, sources = { source } })
  local buf = api.nvim_win_get_buf(win)
  assert(vim.wo[win].wrap == (layout ~= "side_by_side"))
  local stale = toggle(buf)
  assert(not vim.wo[win].wrap)
  toggle(buf)
  handle:resize()
  assert(api.nvim_win_get_buf(win) == buf and vim.wo[win].wrap == (layout ~= "side_by_side"))
  handle:close()
  assert(vim.wo[win].wrap == previous_wrap)
  stale()
  assert(vim.wo[win].wrap == previous_wrap, "Released mappings cannot affect windows")
  api.nvim_win_set_buf(win, original)
  api.nvim_buf_delete(buf, { force = true })
end
local old_mapping = function() end
vim.keymap.set("n", "<M-z>", old_mapping, { buffer = original })
window.configure({ wrap = true })
local handle = diff.render(ctx, patch, { backend = "vim" })
assert(vim.wo[win].wrap, "Configured default must apply to raw diff")
toggle(original)
assert(not vim.wo[win].wrap)
handle:close()
assert(vim.fn.maparg("<M-z>", "n", false, true).callback == old_mapping)
handle = diff.render(ctx, patch, { backend = "vim", wrap = false })
assert(not vim.wo[win].wrap, "Per-call false overrides the default")
handle:close()
window.configure({})

local huge = native.prepare(diff.unified({ string.rep("a", 40000) }, { string.rep("b", 40000) }), {
  layout = "side_by_side",
  wrap = true,
  syntax = false,
  word_diff = false,
}, 18)
assert(api.nvim_buf_line_count(huge) <= 10001, "Wrapped output has a bounded row count")
assert(api.nvim_buf_get_lines(huge, -2, -1, false)[1]:find("…", 1, true), "Truncated wrapped output is marked")
api.nvim_buf_delete(huge, { force = true })

if
  vim.env.SELECTION_TOOLS_DIR
  and vim.fn.filereadable(vim.env.SELECTION_TOOLS_DIR .. "/lua/selection_tools/init.lua") == 1
then
  vim.opt.rtp:prepend(vim.env.SELECTION_TOOLS_DIR)
  local picker = require("selection_tools").open({
    items = { { lines = patch }, { lines = patch } },
    resume = false,
    preview = { enabled = true, providers = { require("git_tools.integrations.selection").diff({ wrap = true }) } },
  })
  local function ready()
    return vim.b[api.nvim_win_get_buf(picker.preview_win)].git_tools_diff == true
  end
  assert(vim.wait(2000, ready, 5))
  assert(vim.wo[picker.preview_win].wrap)
  toggle(picker.input_buf, "i")
  assert(not vim.wo[picker.preview_win].wrap)
  local retired = api.nvim_win_get_buf(picker.preview_win)
  picker:move(1)
  assert(vim.wait(2000, function()
    return ready() and api.nvim_win_get_buf(picker.preview_win) ~= retired
  end, 5))
  assert(not vim.wo[picker.preview_win].wrap, "Picker item changes retain the toggle")
  toggle(picker.list_buf)
  assert(vim.wo[picker.preview_win].wrap)
  picker:close()
end
print(
  "Diff wrap: settings, Unicode columns, continuation highlights, resize, toggles, picker persistence and cleanup passed"
)
vim.cmd("qa!")
