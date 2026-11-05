local root = assert(vim.env.GIT_TOOLS_ROOT)
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. "/../selection-tools.nvim")
vim.o.swapfile = false
vim.cmd.enew()
local api = vim.api
local source, origin = api.nvim_get_current_buf(), api.nvim_get_current_win()
local old = "local old = '" .. string.rep("abcdef中🙂", 10) .. "OLD_END'"
local new = "local new = '" .. string.rep("abcdef中🚀", 10) .. "NEW_END'"
local patch = require("git_tools.diff").unified({ old }, { new }, { old_path = "sample.lua" })
local picker, view, fixture
local function screen(win)
  local top, left = unpack(api.nvim_win_get_position(win))
  local lines = {}
  for row = 1, api.nvim_win_get_height(win) do
    local text = {}
    for col = 1, api.nvim_win_get_width(win) do
      text[#text + 1] = vim.fn.screenstring(top + row, left + col)
    end
    lines[#lines + 1] = table.concat(text)
  end
  return table.concat(lines, "\n")
end
vim.keymap.set("n", "<F6>", function()
  picker = require("selection_tools").open({
    items = { { text = "one", lines = patch }, { text = "two", lines = patch } },
    resume = false,
    preview = {
      enabled = true,
      providers = {
        require("git_tools.integrations.selection").diff({ native = { layout = vim.env.GIT_TOOLS_LAYOUT } }),
      },
    },
  })
end)
vim.keymap.set({ "n", "i" }, "<F8>", function()
  vim.cmd.stopinsert()
  api.nvim_set_current_win(picker.preview_win)
end)
vim.keymap.set({ "n", "i" }, "<F9>", function()
  api.nvim_set_current_win(picker.input_win)
  vim.cmd.startinsert()
end)
vim.keymap.set("n", "<F10>", function()
  fixture = dofile(root .. "/tests/helpers.lua").fixture()
  fixture:write("sample.lua", { old })
  fixture:git("add", ".")
  fixture:git("commit", "-qm", "initial")
  fixture:write("sample.lua", { new })
  view = require("git_tools").compare({ cwd = fixture.root })
end)
vim.keymap.set({ "n", "i" }, "<F12>", function()
  vim.cmd.redraw()
  local result = {
    mode = api.nvim_get_mode().mode,
    origin = api.nvim_get_current_win() == origin,
    source = api.nvim_buf_get_lines(source, 0, -1, false),
    error = vim.v.errmsg,
  }
  if picker and not picker.closed then
    local win = picker.preview_win
    result.picker = {
      wrap = picker.git_tools_diff_wrap == true,
      screen = screen(win),
      width = api.nvim_win_get_width(win),
      buf = api.nvim_win_get_buf(win),
      focus = api.nvim_get_current_win() == picker.input_win,
      query = picker.query,
      selected = picker:current().text,
    }
  end
  if view and view.current and not view.closed then
    result.view = { wrap = {}, screen = {} }
    for _, win in ipairs(view.windows) do
      table.insert(result.view.wrap, vim.wo[win].wrap)
      table.insert(result.view.screen, screen(win))
    end
  end
  vim.fn.writefile({ vim.json.encode(result) }, vim.env.GIT_TOOLS_TUI_DIR .. "/snapshot.json")
end)
api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    if fixture then
      fixture:cleanup()
    end
  end,
})
