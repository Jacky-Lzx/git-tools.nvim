-- Optional, already-loaded provider. Opening a diff never loads/configures pairs.
local M = {}
function M.highlights(lines, ft)
  local rainbow = package.loaded["pairs.rainbow"]
  if rainbow and rainbow.snapshot then
    return rainbow.snapshot(lines, ft)
  end
end
return M
