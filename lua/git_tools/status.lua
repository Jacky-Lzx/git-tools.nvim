local repository = require("git_tools.repository")
local ui = require("git_tools.ui")
local M = {}

function M.open(opts)
  opts = opts or {}
  return ui.pick(opts, "Git changes", function(task, repo, callback)
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
  end, ui.preview(repository.patch, opts))
end

return M
