vim.opt.rtp:prepend(assert(vim.env.GIT_TOOLS_ROOT))
vim.o.swapfile, vim.o.hidden = false, true
vim.g.mapleader = " "
local tools = require("git_tools")
if vim.env.GIT_TOOLS_CONFIG then
  vim.opt.rtp:prepend(vim.env.GIT_TOOLS_CONFIG)
  local spec = dofile(vim.env.GIT_TOOLS_CONFIG .. "/lua/plugins/git/git-tools.lua")[1]
  tools.setup(spec.opts)
  for _, key in ipairs(spec.keys) do
    vim.keymap.set(key.mode or "n", key[1], key[2])
  end
else
  tools.setup({ buffer = { debounce = 20 } })
  vim.keymap.set("n", "<leader>to", tools.toggle_overlay)
  vim.keymap.set("x", "<leader>ggs", function()
    tools.stage_hunk({ range = { vim.fn.line("."), vim.fn.line("v") } })
  end)
  vim.keymap.set({ "o", "x" }, "ih", tools.select_hunk)
end
_G.git_tools_snapshot = function()
  local s = require("git_tools.buffer").states[vim.api.nvim_get_current_buf()]
  local result = {
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    overlay = s and s.overlay,
    hunks = s and #s.hunks or 0,
    index = s and s.index and s.index.text,
    marks = #vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("GitToolsOverlay"), 0, -1, {}),
    mode = vim.fn.mode(),
    error = vim.v.errmsg,
  }
  vim.fn.writefile({ vim.json.encode(result) }, assert(vim.env.GIT_TOOLS_TUI_STATE))
end
