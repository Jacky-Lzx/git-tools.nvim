vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api = vim.api
local diff = require("git_tools.diff")
local native = require("git_tools.diff.native")
local patch = diff.unified("local x = 1\n", "local x = 2\n", { old_path = "main.lua" })
api.nvim_set_hl(0, "Added", { fg = "#00aa00" })
native.prepare(patch, {}, 80)
assert(api.nvim_get_hl(0, { name = "GitToolsDiffAddNumber" }).fg == 0x00aa00)
assert(not api.nvim_get_hl(0, { name = "GitToolsDiffAdd" }).fg, "Backgrounds must preserve syntax foregrounds")

-- Load the real optional provider after the renderer, exercising late attachment.
local root = vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()
local theme_root = vim.fs.dirname(root) .. "/theme-tools.nvim"
if vim.fn.isdirectory(theme_root) == 0 then
  print("SKIP optional theme-tools integration (sibling checkout not installed)")
  vim.cmd("qa!")
  return
end
vim.opt.rtp:prepend(theme_root)
local themes = require("theme_tools")
require("theme_tools.palette").setup({ overrides = { git = { add = "#123456" } } })
api.nvim_exec_autocmds("User", { pattern = "ThemeToolsReady" })
assert(api.nvim_get_hl(0, { name = "GitToolsDiffAddNumber" }).fg == 0x123456)
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
require("theme_tools.palette").setup({ overrides = { git = { add = "#abcdef" }, ui = { border = "#fedcba" } } })
themes.refresh_palette()
assert(api.nvim_get_hl(0, { name = "GitToolsDiffAddNumber" }).fg == 0xabcdef)
assert(api.nvim_get_hl(0, { name = "GitToolsDiffBorder" }).fg == 0xfedcba)
print(
  "Native diff themes: standalone fallback, late theme-tools attachment, real Mocha/Dracula switching and semantic overrides passed"
)
vim.cmd("qa!")
