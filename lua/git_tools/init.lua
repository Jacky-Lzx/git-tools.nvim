-- Requiring the plugin installs no mappings, commands, UI or Git processes.
local M = { diff = require("git_tools.diff") }

function M.browse(opts, callback)
  return require("git_tools.browse").open(opts, callback)
end

function M.status(opts)
  return require("git_tools.status").open(opts)
end

function M.log(opts)
  return require("git_tools.history").open(opts)
end
function M.file_history(opts)
  return M.log(vim.tbl_extend("force", {}, opts or {}, { file = true }))
end
function M.line_history(opts)
  opts = vim.tbl_extend("force", {}, opts or {})
  opts.range = opts.range or { vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_win_get_cursor(0)[1] }
  return M.log(opts)
end
function M.blame(opts, callback)
  return require("git_tools.history").blame(opts, callback)
end

return M
