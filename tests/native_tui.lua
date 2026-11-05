local root = assert(vim.env.GIT_TOOLS_ROOT)
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. "/../selection-tools.nvim")
vim.opt.rtp:prepend(root .. "/../theme-tools.nvim")
vim.o.swapfile = false
local api = vim.api
local themes, diff = require("theme_tools"), require("git_tools.diff")
local layout = vim.env.GIT_TOOLS_LAYOUT or "unified"
local configured = vim.env.GIT_TOOLS_CONFIGURED == "1"
if not configured then
  vim.g.mapleader = " "
  vim.cmd.colorscheme("theme-tools-mocha")
end
themes.refresh_palette()
vim.cmd.enew()
api.nvim_buf_set_name(0, assert(vim.env.GIT_TOOLS_TUI_DIR) .. "/source.lua")
vim.bo.filetype = "lua"
for _, name in ipairs({ "one", "two", "three", "four" }) do
  vim.cmd("normal! i\007u\027gg0Clocal value = '" .. name .. "'\027")
end
local source, origin = api.nvim_get_current_buf(), api.nvim_get_current_win()
local tick = api.nvim_buf_get_changedtick(source)
local picker
local function open()
  local items = {}
  for _, name in ipairs({ "alpha", "beta", "gamma" }) do
    items[#items + 1] = {
      text = name,
      lines = diff.unified({
        'local title = "旧名字"',
        "",
        '    auto("table(%d+)x(%d+)%s", {',
        "",
        "    }, line_begin),",
        "",
        "local count = 12",
        "return title, count",
      }, {
        'local title = "新名字"',
        "",
        "    auto(line_begin, {",
        "",
        '    }, "table(%d+)x(%d+)%s"),',
        "",
        "local count = 34",
        "return title, count -- " .. name,
      }, { old_path = "sample.lua" }),
    }
  end
  picker = require("selection_tools").open({
    items = items,
    resume = false,
    keys = layout == "top_bottom" and { preview_down = { "<C-d>" }, preview_up = { "<C-u>" } } or nil,
    preview = {
      enabled = true,
      providers = { require("git_tools.integrations.selection").diff({ native = { layout = layout } }) },
    },
  })
end
vim.keymap.set("n", "<F6>", open)
vim.keymap.set({ "n", "i" }, "<F7>", function()
  vim.cmd.colorscheme(vim.g.colors_name == "theme-tools-mocha" and "theme-tools-dracula" or "theme-tools-mocha")
  themes.refresh_palette()
end)
-- Observe the actual configured undo mapping, including its backend selection.
local undo = require("selection_tools").undo
require("selection_tools").undo = function(opts)
  picker = undo(opts)
  return picker
end
if not configured then
  vim.keymap.set("n", "<leader>su", function()
    require("selection_tools").undo({ backend = "native", native = { file_header = false } })
  end)
end
vim.keymap.set({ "n", "i" }, "<F12>", function()
  local result = {
    mode = api.nvim_get_mode().mode,
    source = api.nvim_buf_get_lines(source, 0, -1, false),
    unchanged = api.nvim_buf_get_changedtick(source) == tick,
    origin = api.nvim_get_current_win() == origin,
    theme = vim.g.colors_name,
    add = api.nvim_get_hl(0, { name = "GitToolsDiffAddNumber" }).fg,
    error = vim.v.errmsg,
    native_buffers = 0,
  }
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.b[buf].git_tools_diff then
      result.native_buffers = result.native_buffers + 1
    end
  end
  if picker and not picker.closed then
    local buf = api.nvim_win_get_buf(picker.preview_win)
    result.picker = {
      query = picker.query,
      count = #picker.matches,
      selected = picker:current() and picker:current().text,
      lines = api.nvim_buf_get_lines(buf, 0, -1, false),
      buf = buf,
      native = vim.b[buf].git_tools_diff == true,
      layout = vim.b[buf].git_tools_diff_layout or "unified",
      focus = api.nvim_get_current_win() == picker.input_win,
      wrap = picker.git_tools_diff_wrap == true,
      window_wrap = vim.wo[picker.preview_win].wrap,
      compare = picker.opts.compare,
      width = api.nvim_win_get_width(picker.preview_win),
      height = api.nvim_win_get_height(picker.preview_win),
      topline = api.nvim_win_call(picker.preview_win, function()
        return vim.fn.winsaveview().topline
      end),
    }
    result.picker.emphasis = {}
    for _, mark in
      ipairs(api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsDiff"), 0, -1, { details = true }))
    do
      if (mark[4].hl_group or ""):match("Text$") then
        local text = result.picker.lines[mark[2] + 1]
        result.picker.emphasis[text] = true
      end
    end
    vim.cmd.redraw()
    local top, left = unpack(api.nvim_win_get_position(picker.preview_win))
    local screen = {}
    for row = 1, api.nvim_win_get_height(picker.preview_win) do
      local chars = {}
      for col = 1, result.picker.width do
        chars[#chars + 1] = vim.fn.screenstring(top + row, left + col)
      end
      screen[#screen + 1] = table.concat(chars)
    end
    result.picker.screen = table.concat(screen, "\n")
  end
  vim.fn.writefile({ vim.json.encode(result) }, vim.env.GIT_TOOLS_TUI_DIR .. "/snapshot.json")
end)
