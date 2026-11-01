local M = {}
function M.open(opts)
  return require("git_tools.changes").open(vim.tbl_extend("force", { group = true }, opts or {}))
end
return M
