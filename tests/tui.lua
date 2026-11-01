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
  vim.keymap.set("n", "<C-g>", tools.lazygit)
end
if vim.env.GIT_TOOLS_TEST_LAZYGIT_CONFIG then
  require("git_tools.lazygit").configure({ args = { "--use-config-dir", vim.env.GIT_TOOLS_TEST_LAZYGIT_CONFIG } })
end
_G.git_tools_snapshot = function()
  local s = require("git_tools.buffer").states[vim.api.nvim_get_current_buf()]
  local result = {
    filetype = vim.bo.filetype,
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    overlay = s and s.overlay,
    hunks = s and #s.hunks or 0,
    index = s and s.index and s.index.text,
    marks = #vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("GitToolsOverlay"), 0, -1, {}),
    mode = vim.fn.mode(),
    error = vim.v.errmsg,
  }
  local lazygit = package.loaded["git_tools.lazygit"]
  local session = lazygit and lazygit.current
  if session then
    result.lazygit = {
      job = session.job,
      running = not session.exited,
      width = vim.api.nvim_win_get_width(session.win),
      relative = vim.api.nvim_win_get_config(session.win).relative,
    }
  end
  vim.fn.writefile({ vim.json.encode(result) }, assert(vim.env.GIT_TOOLS_TUI_STATE))
end
