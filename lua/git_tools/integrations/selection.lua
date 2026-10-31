-- Optional provider adapter. No selection-tools module is loaded here.
local M = {}

function M.diff(opts)
  opts = opts or {}
  return function(ctx)
    local item = ctx.item
    local lines = opts.lines and opts.lines(item) or type(item) == "table" and item.lines
    if not lines then
      return false
    end
    local config = vim.tbl_extend("force", {}, opts)
    config.cwd = opts.cwd or type(item) == "table" and item.root or nil
    return require("git_tools.diff").render(ctx, lines, config)
  end
end

return M
