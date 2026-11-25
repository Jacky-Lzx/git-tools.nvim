local M = {}

local defaults = {
  buffer = { signs = false, numhl = true, word_diff = false, line_blame = false, debounce = 100 },
  compare = {
    keymap = { panel = { ["<CR>"] = "open", ["<Tab>"] = "next_file", R = "refresh", q = "close" } },
  },
  diff = { wrap = false },
  lazygit = { command = "lazygit", args = {}, width = 0.9, height = 0.9, border = "rounded", theme = true },
  command = { default = "menu" },
}
local rules = { replace = { { "compare", "keymap", "panel" } } }
local instance

function M.defaults(...)
  -- Direct feature calls can use the built-in defaults before setup().
  return vim.deepcopy(vim.tbl_get(defaults, ...))
end

function M.instance()
  if not instance then
    instance = require("base_tools.config").new(defaults, rules)
  end
  return instance
end

function M.reset()
  if instance then
    instance:reset()
  end
end

return M
