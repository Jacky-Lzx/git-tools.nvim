vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api = vim.api
local function get(name)
  return api.nvim_get_hl(0, { name = name, link = false })
end

-- Dracula's DiffAdd paints dark text on green; its syntax color is green text.
api.nvim_set_hl(0, "DiffAdd", { fg = 0x282a36, bg = 0x50fa7b })
api.nvim_set_hl(0, "diffAdded", { fg = 0x50fa7b })
api.nvim_set_hl(0, "DiffChange", { fg = 0xffb86c })
api.nvim_set_hl(0, "DiffDelete", { fg = 0xff5555 })
local buffer = require("git_tools.buffer")
buffer.setup()
assert(get("GitToolsAdd").fg == 0x50fa7b and not get("GitToolsAdd").bg)
assert(get("GitToolsChange").fg == 0xffb86c and not get("GitToolsChange").bg)
assert(get("GitToolsDelete").fg == 0xff5555 and not get("GitToolsDelete").bg)
assert(get("GitToolsAddLine").bg == 0x50fa7b, "Diff overlay lost its background")

-- Links follow subsequent theme changes without freezing a resolved color.
api.nvim_set_hl(0, "diffAdded", { fg = 0xa6e3a1 })
api.nvim_exec_autocmds("ColorScheme", {})
assert(get("GitToolsAdd").fg == 0xa6e3a1 and not get("GitToolsAdd").bg)

-- Themes without syntax-specific groups use Neovim's foreground-only fallback.
vim.cmd("highlight clear diffAdded")
api.nvim_exec_autocmds("ColorScheme", {})
assert(get("GitToolsAdd").fg == get("Added").fg and not get("GitToolsAdd").bg)

-- User/theme overrides remain authoritative.
api.nvim_set_hl(0, "GitToolsAdd", { fg = 0x123456 })
api.nvim_exec_autocmds("ColorScheme", {})
buffer.setup()
assert(get("GitToolsAdd").fg == 0x123456)
print("Git gutter highlights: foreground additions, overlays, theme changes, fallback and overrides passed")

-- Staged colors retain their hue at half intensity and follow theme changes.
api.nvim_set_hl(0, "Normal", { fg = 0xffffff, bg = 0x202020 })
api.nvim_set_hl(0, "GitToolsAdd", { fg = 0x60a0e0 })
api.nvim_exec_autocmds("ColorScheme", {})
assert(get("GitToolsStagedAdd").fg == 0x406080)
api.nvim_set_hl(0, "GitToolsStagedDelete", { fg = 0x123456 })
api.nvim_exec_autocmds("ColorScheme", {})
assert(get("GitToolsStagedDelete").fg == 0x123456)

local h = require("git_tools.hunks")
local buf = api.nvim_create_buf(true, false)
local function draw(head, index, text)
  api.nvim_buf_set_lines(buf, 0, -1, false, h.text(text).lines)
  local s =
    { buf = buf, name = api.nvim_buf_get_name(buf), head = h.text(head), index = h.text(index), text = h.text(text) }
  s.hunks, s.staged = h.diff(s.index, s.text), h.diff(s.head, s.index)
  buffer.states[buf] = s
  buffer.draw(s)
  local result = {}
  for _, mark in
    ipairs(api.nvim_buf_get_extmarks(buf, api.nvim_get_namespaces().GitToolsSigns, 0, -1, { details = true }))
  do
    local line, detail = mark[2] + 1, mark[4]
    if detail.number_hl_group and (not result[line] or detail.priority > result[line].priority) then
      result[line] = { group = detail.number_hl_group, priority = detail.priority }
    end
  end
  return result
end
local marks = draw("a\nb\nc\nd\n", "a\nB\nc\nd\n", "insert\na\nB\nc\nD\n")
assert(marks[3].group == "GitToolsStagedChange")
assert(marks[1].group == "GitToolsAdd" and marks[5].group == "GitToolsChange")
marks = draw("a\nb\n", "a\nB\n", "a\nBB\n")
assert(marks[2].group == "GitToolsChange", "Unstaged changes must win overlapping number highlights")
marks = draw("a\nb\n", "a\nnew\nb\n", "a\nnew\nb\n")
assert(marks[2].group == "GitToolsStagedAdd")
marks = draw("a\nb\nc\n", "a\nc\n", "a\nc\n")
assert(marks[1].group == "GitToolsStagedDelete")
marks = draw("a\nb\nc\n", "a\nB\nc\n", "a\nc\n")
assert(not marks[2], "Deleted staged lines must not color unrelated surviving lines")
buffer.toggle("numhl", false)
assert(#api.nvim_buf_get_extmarks(buf, api.nvim_get_namespaces().GitToolsSigns, 0, -1, {}) == 0)
buffer.dispose()
print("Staged gutter: muted colors, projection, overlap, deletion and toggle passed")
