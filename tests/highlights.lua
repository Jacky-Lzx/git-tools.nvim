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
