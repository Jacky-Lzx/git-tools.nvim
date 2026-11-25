local M = {}

local instance

local standalone_defaults = {
  diff = { wrap = false },
  lazygit = { command = "lazygit", args = {}, width = 0.9, height = 0.9, border = "rounded", theme = true },
}

local defined_defaults, definition_options

local function configuration()
  if not defined_defaults then
    local config = require("base_tools.config")
    local validators = require("base_tools.config.validators")
    local boolean = validators.type("boolean")
    defined_defaults, definition_options = config.compile_definition({
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
    })
  end
  return defined_defaults, definition_options
end

function M.buffer_instance(opts)
  local _, options = configuration()
  return require("base_tools.config").new({ buffer = opts }, { schema = { buffer = options.schema.buffer } })
end

function M.defaults(...)
  local section = ...
  if standalone_defaults[section] ~= nil then
    return vim.deepcopy(vim.tbl_get(standalone_defaults, ...))
  end
  local defined = configuration()
  if select("#", ...) == 0 then
    return vim.deepcopy(vim.tbl_extend("force", standalone_defaults, defined))
  end
  return vim.deepcopy(vim.tbl_get(defined, ...))
end

function M.instance()
  if not instance then
    local config = require("base_tools.config")
    local defined, options = configuration()
    instance = config.new(vim.tbl_extend("force", standalone_defaults, defined), options)
  end
  return instance
end

function M.reset()
  if instance then
    instance:reset()
  end
end

return M
