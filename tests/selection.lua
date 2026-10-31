vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
vim.opt.rtp:prepend(assert(vim.env.SELECTION_TOOLS_DIR))
local api = vim.api
local diff = require("git_tools.diff")
local provider = require("git_tools.integrations.selection")
local patch = diff.unified({ "local value = 1" }, { "local value = 2" }, { old_path = "main.lua" })
local function wait(test)
  assert(vim.wait(5000, test, 5), "preview did not become ready")
end
local function run(backend)
  local p = require("selection_tools").open({
    items = { { lines = patch }, { lines = { "No text edits; command only." } } },
    resume = false,
    preview = { enabled = true, providers = { provider.diff({ backend = backend }) } },
  })
  wait(function()
    local buf = api.nvim_win_get_buf(p.preview_win)
    return backend == "delta" and vim.bo[buf].buftype == "terminal"
      or backend == "vim" and vim.bo[buf].filetype == "diff"
  end)
  local frame = api.nvim_win_get_buf(p.preview_win)
  p:move(1)
  wait(function()
    return api.nvim_win_get_buf(p.preview_win) == p.preview_buf
      and (api.nvim_buf_get_lines(p.preview_buf, 0, 1, false)[1] or ""):find("command only", 1, true)
  end)
  assert(api.nvim_buf_get_lines(p.preview_buf, 0, 1, false)[1]:find("command only", 1, true))
  if backend == "delta" then
    assert(not api.nvim_buf_is_valid(frame), "retired ANSI frame was not released")
  end
  p:move(-1)
  wait(function()
    local buf = api.nvim_win_get_buf(p.preview_win)
    return backend == "delta" and vim.bo[buf].buftype == "terminal"
      or backend == "vim" and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == patch[1]
  end)
  local final_frame = api.nvim_win_get_buf(p.preview_win)
  p:close()
  assert(not api.nvim_buf_is_valid(final_frame))
end
run("vim")
local backends = "native"
if vim.fn.executable("delta") == 1 then
  run("delta")
  backends = backends .. "/ANSI"
else
  print("SKIP real delta integration (delta not installed)")
end
print("git-tools selection adapter: " .. backends .. " previews, switching and owned-frame cleanup passed")
vim.cmd("qa!")
