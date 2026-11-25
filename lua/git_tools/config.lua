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
local effective = defaults

function M.defaults(...)
  -- Direct feature calls can use the built-in defaults before setup().
  return vim.deepcopy(vim.tbl_get(defaults, ...))
end

function M.resolve(opts)
  return require("base_tools.config").merge(defaults, opts, rules)
end

function M.get(...)
  return require("base_tools.config").get(effective, ...)
end

function M.publish(opts)
  effective = opts and vim.deepcopy(opts) or defaults
end

return M
