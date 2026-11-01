local M = {}

function M.diff()
  local status = vim.b.git_tools_status or {}
  return { added = status.added or 0, modified = status.changed or 0, removed = status.removed or 0 }
end

function M.branch()
  return (vim.b.git_tools_status or {}).head or ""
end

function M.scrollbar()
  if M.registered then
    return true
  end
  local ok, scrollbar = pcall(require, "scrollbar.handlers")
  if not ok then
    return false
  end
  scrollbar.register("git_tools", function(buf)
    local marks = {}
    for _, change in ipairs(require("git_tools.buffer").get_hunks(buf)) do
      local first, last = require("git_tools.hunks").bounds(change)
      local kind = change.old_count == 0 and "GitAdd" or change.new_count == 0 and "GitDelete" or "GitChange"
      for line = first, last do
        marks[#marks + 1] = { line = line, type = kind, level = 1 }
      end
    end
    return marks
  end)
  M.registered = true
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("GitToolsScrollbar", { clear = true }),
    pattern = "GitToolsUpdate",
    callback = function()
      require("scrollbar").render()
    end,
  })
  return true
end

return M
