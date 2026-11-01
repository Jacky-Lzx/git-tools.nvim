local repository = require("git_tools.repository")
local ui = require("git_tools.ui")
local operations = require("git_tools.operations")
local M = {}

function M.open(opts)
  opts = opts or {}
  local repo
  local function load(task, current, callback)
    repo = current
    repository.status(task, repo, function(err, items)
      if err then
        callback(err)
        return
      end
      if opts.kind then
        items = vim.tbl_filter(function(item)
          return item.kind == opts.kind
        end, items)
      end
      callback(nil, items)
    end)
  end
  local controller = operations.controller(function(task, callback)
    load(task, repo, callback)
  end)
  local actions = {}
  for _, name in ipairs({ "stage", "unstage", "restore" }) do
    actions[name] = function(picker)
      local items = vim.deepcopy(picker:selected({ fallback = true }))
      controller:run(picker, function(done)
        operations.files(name, items, opts, done)
      end)
    end
  end
  actions.refresh = function(picker)
    controller:refresh(picker)
  end
  return ui.pick(opts, "Git changes", load, ui.preview(repository.patch, opts), nil, {
    multi = true,
    actions = actions,
    keys = { stage = { "<C-s>" }, unstage = { "<C-z>" }, restore = { "<C-r>" }, refresh = { "<F5>" } },
    on_close = function()
      controller:close()
    end,
  })
end

return M
