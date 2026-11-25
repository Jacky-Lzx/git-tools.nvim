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
local buffer_toggles = { "signs", "numhl", "word_diff", "line_blame" }
local instance

local function validate_toggle_value(name, value)
  assert(type(value) == "boolean", "buffer." .. name .. " must be boolean")
end

function M.validate_buffer_toggle(name, value)
  assert(vim.tbl_contains(buffer_toggles, name), "Unknown buffer toggle: " .. tostring(name))
  validate_toggle_value(name, value)
end

function M.validate_buffer(opts)
  assert(type(opts) == "table", "buffer must be a table or false")
  for _, name in ipairs(buffer_toggles) do
    validate_toggle_value(name, opts[name])
  end
  assert(
    type(opts.debounce) == "number" and opts.debounce >= 0 and opts.debounce < math.huge,
    "buffer.debounce must be a finite nonnegative number"
  )
  assert(opts.on_attach == nil or type(opts.on_attach) == "function", "buffer.on_attach must be a function")
end

function M.defaults(...)
  -- Direct feature calls can use the built-in defaults before setup().
  return vim.deepcopy(vim.tbl_get(defaults, ...))
end

function M.instance()
  if not instance then
    instance = require("base_tools.config").new(defaults, {
      replace = { { "compare", "keymap", "panel" } },
      validate = function(candidate)
        if candidate.buffer ~= false then
          M.validate_buffer(candidate.buffer)
        end
      end,
    })
  end
  return instance
end

function M.reset()
  if instance then
    instance:reset()
  end
end

return M
