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
local instance

local function boolean(value)
  return type(value) == "boolean", "must be boolean"
end

local buffer_options = {
  signs = boolean,
  numhl = boolean,
  word_diff = boolean,
  line_blame = boolean,
  debounce = function(value)
    return type(value) == "number" and value >= 0 and value < math.huge, "must be a finite nonnegative number"
  end,
  on_attach = function(value)
    return value == nil or type(value) == "function", "must be a function"
  end,
}

function M.assert_buffer_toggle(name)
  assert(buffer_options[name] == boolean, "Unknown buffer toggle: " .. tostring(name))
end

function M.validate_buffer_option(name, value)
  local valid, message = buffer_options[name](value)
  assert(valid, "buffer." .. name .. " " .. message)
end

function M.validate_buffer(opts)
  assert(type(opts) == "table", "buffer must be a table or false")
  for name in pairs(buffer_options) do
    M.validate_buffer_option(name, opts[name])
  end
end

local function buffer_fields()
  local fields = {
    {
      path = { "buffer" },
      validate = function(value)
        return value == false or type(value) == "table", "must be a table or false"
      end,
    },
  }
  local names = vim.tbl_keys(buffer_options)
  table.sort(names)
  for _, name in ipairs(names) do
    local validate = buffer_options[name]
    fields[#fields + 1] = {
      path = { "buffer", name },
      validate = function(value, get)
        if get("buffer") == false then
          return true
        end
        return validate(value)
      end,
    }
  end
  return fields
end

function M.defaults(...)
  -- Direct feature calls can use the built-in defaults before setup().
  return vim.deepcopy(vim.tbl_get(defaults, ...))
end

function M.instance()
  if not instance then
    instance = require("base_tools.config").new(defaults, {
      replace = { { "compare", "keymap", "panel" } },
      fields = buffer_fields(),
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
