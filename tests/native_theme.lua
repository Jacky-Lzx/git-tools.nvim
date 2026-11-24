vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api = vim.api
local diff = require("git_tools.diff")
local native = require("git_tools.diff.native")
local patch = diff.unified("local x = 1\n", "local x = 2\n", { old_path = "main.lua" })
api.nvim_set_hl(0, "Added", { fg = "#00aa00" })
native.prepare(patch, {}, 80)
assert(api.nvim_get_hl(0, { name = "GitToolsDiffAddNumber" }).fg == 0x00aa00)
assert(not api.nvim_get_hl(0, { name = "GitToolsDiffAdd" }).fg, "Backgrounds must preserve syntax foregrounds")
-- Native comparison panes must avoid bright/reversed theme DiffAdd colors.
api.nvim_set_hl(0, "Normal", { bg = "#282a36", fg = "#f8f8f2" })
api.nvim_set_hl(0, "DiffAdd", { fg = "#50fa7b", reverse = true })
api.nvim_exec_autocmds("ColorScheme", {})
vim.wo.winhighlight = "Normal:Normal,DiffAdd:DiffAdd"
require("git_tools.diff.theme").window(0)
assert(vim.wo.winhighlight:find("Normal:Normal", 1, true))
assert(not vim.wo.winhighlight:find("DiffAdd:DiffAdd", 1, true))
local add = api.nvim_get_hl(0, { name = "GitToolsDiffAdd" })
assert(add.bg == 0x243731 and not add.reverse and not add.fg, "Blend only 10 percent green into the background")
assert(api.nvim_get_hl(0, { name = "DiffAdd" }).reverse, "Do not change global theme highlights")

-- Load the real optional provider after the renderer, exercising late attachment.
local root = vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()
local theme_root = vim.fs.dirname(root) .. "/theme-tools.nvim"
if vim.fn.isdirectory(theme_root) == 0 then
  print("SKIP optional theme-tools integration (sibling checkout not installed)")
  vim.cmd("qa!")
  return
end
local fixture = dofile(root .. "/tests/helpers.lua").fixture()
vim.fn.mkdir(fixture.root .. "/src", "p")
fixture:write("src/main.lua", { "local x = 1" })
fixture:git("add", "src/main.lua")
fixture:git("commit", "-qm", "initial")
fixture:write("src/main.lua", { "local x = 2" })
local view = require("git_tools").compare({ cwd = fixture.root })
assert(
  vim.wait(5000, function()
    return view.current ~= nil
  end, 5),
  "Comparison did not open"
)
local rows_ns = api.nvim_get_namespaces()["git_tools.view.panel.rows"]
local function panel_marks()
  return api.nvim_buf_get_extmarks(view.panel, rows_ns, 0, -1, { details = true })
end
local plain = panel_marks()
assert(#plain == 2)
assert(plain[1][4].hl_group == "GitToolsCompareDirectory" and plain[2][4].hl_group == "GitToolsCompareChange")
assert(vim.wo[view.panel_win].winhighlight:find("Normal:GitToolsCompareNormal", 1, true))
local panel_tick = api.nvim_buf_get_changedtick(view.panel)
local panel_cursor = api.nvim_win_get_cursor(view.panel_win)
local focused_win = api.nvim_get_current_win()

vim.opt.rtp:prepend(theme_root)
local themes = require("theme_tools")
require("theme_tools.palette").setup({ overrides = { git = { add = "#123456" } } })
themes.icons.setup({ providers = { "ascii", "none" }, default = "ascii", persist = false })
api.nvim_exec_autocmds("User", { pattern = "ThemeToolsReady" })
assert(api.nvim_get_hl(0, { name = "GitToolsDiffAddNumber" }).fg == 0x123456)
local folder_icon, folder_hl = themes.icons.get("directory", "src")
local icon, icon_hl = themes.icons.get("file", "src/main.lua")
local function assert_panel_icons()
  local marks = panel_marks()
  assert(#marks == 4 and marks[2][3] == 4 and marks[4][3] == 6, "Icons must precede their names")
  assert(vim.deep_equal(marks[2][4].virt_text, { { folder_icon .. " ", folder_hl } }), "Use the theme folder icon")
  assert(vim.deep_equal(marks[4][4].virt_text, { { icon .. " ", icon_hl } }), "Use the theme file icon")
end
assert_panel_icons()
assert(themes.icons.set("none"))
assert(#panel_marks() == 2, "Hiding icons should retain the directory and status highlights")
assert(themes.icons.set("ascii"))
assert_panel_icons()
require("theme_tools.palette").setup({})
vim.cmd.colorscheme("theme-tools-mocha")
themes.refresh_palette()
local mocha = themes.palette()
assert(api.nvim_get_hl(0, { name = "GitToolsDiffAddNumber" }).fg == tonumber(mocha.git.add:sub(2), 16))
local old_background = api.nvim_get_hl(0, { name = "GitToolsDiffAdd" }).bg
local buf = native.prepare(patch, {}, 80)
local tick = api.nvim_buf_get_changedtick(buf)
vim.cmd.colorscheme("theme-tools-dracula")
themes.refresh_palette()
local dracula = themes.palette()
assert(api.nvim_get_hl(0, { name = "GitToolsDiffDeleteNumber" }).fg == tonumber(dracula.git.delete:sub(2), 16))
assert(api.nvim_get_hl(0, { name = "GitToolsDiffAdd" }).bg ~= old_background)
assert(api.nvim_buf_get_changedtick(buf) == tick, "Theme changes must recolor without rebuilding the preview")
assert(api.nvim_get_hl(0, { name = "GitToolsCompareNormal" }).bg == tonumber(dracula.ui.sidebar_bg:sub(2), 16))
assert(api.nvim_get_hl(0, { name = "GitToolsCompareChange" }).fg == tonumber(dracula.git.change:sub(2), 16))
require("theme_tools.palette").setup({ overrides = { git = { add = "#abcdef" }, ui = { border = "#fedcba" } } })
themes.refresh_palette()
assert(api.nvim_get_hl(0, { name = "GitToolsDiffAddNumber" }).fg == 0xabcdef)
assert(api.nvim_get_hl(0, { name = "GitToolsDiffBorder" }).fg == 0xfedcba)
assert(api.nvim_buf_get_changedtick(view.panel) == panel_tick, "Theme and icon changes must preserve panel text")
assert(vim.deep_equal(api.nvim_win_get_cursor(view.panel_win), panel_cursor))
assert(api.nvim_get_current_win() == focused_win and view.current.path == "src/main.lua")
view:close()
assert(themes.icons.set("none"))
fixture:cleanup()
print(
  "Diff and compare themes: fallback, late theme-tools attachment, live palettes, tree icons and preserved selection passed"
)
vim.cmd("qa!")
