local M = {}

local instance

local standalone_defaults = {
  diff = { wrap = false },
  lazygit = { command = "lazygit", args = {}, width = 0.9, height = 0.9, border = "rounded", theme = true },
}

local definition

local function configuration()
  if not definition then
    local validators = require("base_tools.config.validators")
    local boolean = validators.type("boolean")
    definition = {
      diff = { default = standalone_defaults.diff },
      lazygit = { default = standalone_defaults.lazygit },
      buffer = {
        default_choice = "enabled",
        choices = {
          enabled = {
            fields = {
              signs = { default = false, validate = boolean },
              numhl = { default = true, validate = boolean },
              word_diff = { default = false, validate = boolean },
              line_blame = { default = false, validate = boolean },
              debounce = { default = 100, validate = validators.range(0) },
              on_attach = { validate = validators.optional(validators.type("function")) },
            },
          },
          disabled = { value = false },
        },
      },
      compare = {
        fields = {
          keymap = {
            fields = {
              panel = {
                default = { ["<CR>"] = "open", ["<Tab>"] = "next_file", R = "refresh", q = "close" },
                replace = true,
              },
            },
          },
        },
      },
      command = { fields = { default = { default = "menu" } } },
    }
  end
  return definition
end

function M.buffer_instance(opts)
  local store = require("base_tools.config").new({ buffer = configuration().buffer })
  store:change({ "buffer" }, opts)
  return store
end

function M.defaults(...)
  local section = ...
  if standalone_defaults[section] ~= nil then
    return vim.deepcopy(vim.tbl_get(standalone_defaults, ...))
  end
  local defaults = M.instance():resolve()
  if select("#", ...) == 0 then
    return defaults
  end
  return vim.tbl_get(defaults, ...)
end

function M.instance()
  if not instance then
    instance = require("base_tools.config").new(configuration())
  end
  return instance
end

function M.reset()
  if instance then
    instance:reset()
  end
end

return M
