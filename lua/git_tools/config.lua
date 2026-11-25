local M = {}

local instance

local validators = require("base_tools.config.validators")
local boolean = validators.type("boolean")

local definition = {
  diff = { fields = { wrap = { default = false, validate = boolean } } },
  lazygit = {
    default = { command = "lazygit", args = {}, width = 0.9, height = 0.9, border = "rounded", theme = true },
  },
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

function M.section_instance(name)
  local entry = assert(definition[name], "Unknown config section: " .. name)
  return require("base_tools.config").new({ [name] = entry })
end

function M.buffer_instance(opts)
  local store = M.section_instance("buffer")
  store:change({ "buffer" }, opts)
  return store
end

function M.defaults(...)
  local defaults = M.instance():resolve()
  if select("#", ...) == 0 then
    return defaults
  end
  return vim.tbl_get(defaults, ...)
end

function M.instance()
  if not instance then
    instance = require("base_tools.config").new(definition)
  end
  return instance
end

function M.reset()
  if instance then
    instance:reset()
  end
end

return M
