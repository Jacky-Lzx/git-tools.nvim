-- Requiring the plugin installs no mappings, commands, UI or Git processes.
local M = { diff = require("git_tools.diff") }

function M.status(opts)
  return require("git_tools.status").open(opts)
end

return M
