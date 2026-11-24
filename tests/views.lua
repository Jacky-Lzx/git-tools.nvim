vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api, tools = vim.api, require("git_tools")
vim.o.columns = 160
vim.o.lines = 45
vim.o.hidden = true
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local function command(...)
  local args = { "git", "-C", root, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null" }
  vim.list_extend(args, { ... })
  return vim.system(args):wait()
end
local function git(...)
  local result = command(...)
  assert(result.code == 0, result.stderr)
  return result.stdout
end
git("init", "-qb", "main")
git("config", "user.name", "Fixture")
git("config", "user.email", "fixture@example.invalid")
vim.fn.writefile({ "base" }, root .. "/a.txt")
vim.fn.writefile({ "other" }, root .. "/b.txt")
git("add", ".")
git("commit", "-qm", "initial")
local initial = git("rev-parse", "HEAD"):gsub("\n$", "")
vim.fn.writefile({ "index" }, root .. "/a.txt")
git("add", "a.txt")
vim.fn.writefile({ "disk" }, root .. "/a.txt")
local working = vim.fn.bufadd(root .. "/a.txt")
vim.fn.bufload(working)
local function original_tab() end
vim.keymap.set("n", "<Tab>", original_tab, { buffer = working })
local function wait(test, message)
  assert(vim.wait(5000, test, 5), message or "View timeout")
end
local function text(win)
  return table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false), "\n")
end
local function tab_mapping()
  return vim.fn.maparg("<Tab>", "n", false, true).callback
end
local view = tools.compare({ cwd = root })
wait(function()
  return view.current ~= nil
end)
assert(view.current.kind == "staged" and text(view.windows[1]) == "base" and text(view.windows[2]) == "index")
local function balanced()
  local widths = {}
  local column = api.nvim_win_get_position(view.panel_win)[2]
  for _, win in ipairs(view.windows) do
    widths[#widths + 1] = api.nvim_win_get_width(win)
    local pane_column = api.nvim_win_get_position(win)[2]
    assert(pane_column > column, "Comparison panes must appear in order to the right of the file panel")
    column = pane_column
  end
  table.sort(widths)
  assert(widths[#widths] - widths[1] <= 1, "Diff panes must share available width equally: " .. vim.inspect(widths))
end
balanced()
assert(not vim.wo[view.panel_win].number and not vim.wo[view.panel_win].relativenumber)
assert(vim.wo[view.windows[2]].winbar:find("Index", 1, true))
assert(api.nvim_buf_get_lines(view.panel, 0, 1, false)[1] == " S  a.txt")
for _, win in ipairs(view.windows) do
  assert(vim.wo[win].winhighlight:find("DiffAdd:GitToolsDiffAdd", 1, true), "Use subtle pane-local diff colors")
end
assert(not vim.wo[view.windows[1]].wrap and not vim.wo[view.windows[2]].wrap)
api.nvim_set_current_win(view.windows[1])
local wrap_mapping = vim.fn.maparg("<M-z>", "n", false, true).callback
wrap_mapping()
assert(vim.wo[view.windows[1]].wrap and vim.wo[view.windows[2]].wrap, "Alt+Z toggles both panes")
tab_mapping()()
wait(function()
  return view.current.kind == "unstaged"
end)
assert(text(view.windows[1]) == "index" and text(view.windows[2]) == "disk")
assert(api.nvim_get_current_win() == view.windows[1], "Tab keeps focus in the same diff pane")
assert(api.nvim_win_get_cursor(view.panel_win)[1] == 2, "Panel selection follows displayed file")
assert(vim.wo[view.windows[2]].winbar:find("Working tree", 1, true))
vim.o.columns = 120
api.nvim_exec_autocmds("VimResized", {})
balanced()
assert(vim.wo[view.windows[1]].diff and vim.wo[view.windows[2]].diff)
assert(vim.wo[view.windows[1]].wrap and vim.wo[view.windows[2]].wrap, "Changing files retains wrap")
api.nvim_set_current_win(view.windows[2])
assert(tab_mapping() ~= original_tab, "The active working pane should advance files")
vim.cmd.tabprevious()
assert(api.nvim_buf_call(working, tab_mapping) == original_tab, "Leaving compare must restore the working buffer's Tab")
api.nvim_set_current_win(view.panel_win)
tab_mapping()()
wait(function()
  return view.current.kind == "staged"
end)
assert(api.nvim_get_current_win() == view.panel_win, "Tab wraps around and keeps focus in the file panel")
tab_mapping()()
wait(function()
  return view.current.kind == "unstaged"
end)
local actual = view.result
api.nvim_buf_set_lines(actual, 0, -1, false, { "unsaved" })
view:close()
assert(api.nvim_buf_is_valid(actual) and vim.bo[actual].modified, "Closing diff must preserve unsaved file buffer")
assert(vim.fn.maparg("q", "n", false, true).buffer ~= 1, "View mappings must be released")
assert(api.nvim_buf_call(working, tab_mapping) == original_tab, "Closing compare must preserve the prior Tab mapping")
view = tools.compare({ cwd = root, commit = initial, wrap = true })
wait(function()
  return view.current ~= nil
end)
assert(text(view.windows[1]) == "" and text(view.windows[2]) == "base", "Root commit uses an empty left side")
assert(vim.wo[view.windows[1]].wrap and vim.wo[view.windows[2]].wrap, "Explicit wrap applies after diffthis")
view:close()
git("add", "a.txt")
git("commit", "-qm", "changed")
view = tools.compare({ cwd = root, from = initial, to = "HEAD" })
wait(function()
  return view.current ~= nil
end)
assert(
  text(view.windows[1]) == "base" and text(view.windows[2]) == "disk",
  "Revision comparison must ignore unsaved buffer"
)
view:close()
tools.setup({ buffer = false })
local original_cwd = vim.fn.getcwd()
vim.cmd.tcd(vim.fn.fnameescape(root))
local moved_focus = false
local focus_probe = api.nvim_create_autocmd("OptionSet", {
  pattern = "bufhidden",
  callback = function()
    if not moved_focus and view.windows and #view.windows == 1 then
      moved_focus = true
      api.nvim_set_current_win(view.panel_win)
    end
  end,
})
local reversed_panes = false
local order_probe = api.nvim_create_autocmd("OptionSet", {
  pattern = "winbar",
  callback = function()
    if reversed_panes or not vim.v.option_new:find("HEAD~1", 1, true) then
      return
    end
    local working, revision = unpack(view.windows)
    api.nvim_win_set_config(working, { win = revision, split = "right" })
    reversed_panes = api.nvim_win_get_position(working)[2] > api.nvim_win_get_position(revision)[2]
  end,
})
vim.cmd("GitTools compare")
view = assert(next(require("git_tools.view").active), "The compare command must open a view")
wait(function()
  return view.current ~= nil
end)
api.nvim_del_autocmd(focus_probe)
api.nvim_del_autocmd(order_probe)
assert(moved_focus, "The focus probe must run while the comparison splits are created")
assert(reversed_panes, "The order probe must reverse the physical panes after creating them")
assert(text(view.windows[1]) == "unsaved" and text(view.windows[2]) == "base")
assert(view.result == actual and api.nvim_win_get_buf(view.windows[1]) == actual and vim.bo[actual].modifiable)
assert(not vim.bo[api.nvim_win_get_buf(view.windows[2])].modifiable)
assert(vim.wo[view.windows[1]].winbar:find("Working tree", 1, true))
assert(vim.wo[view.windows[2]].winbar:find("HEAD~1", 1, true))
assert(api.nvim_get_current_win() == view.windows[1])
balanced()
view:close()
vim.cmd("GitTools compare HEAD")
view = assert(next(require("git_tools.view").active), "The compare command must accept an explicit revision")
wait(function()
  return view.current ~= nil
end)
assert(text(view.windows[1]) == "unsaved" and text(view.windows[2]) == "disk")
view:close()
vim.cmd.tcd(vim.fn.fnameescape(original_cwd))
api.nvim_buf_delete(actual, { force = true })
git("reset", "--hard", initial)
vim.cmd.edit(root .. "/b.txt")
local unsaved = api.nvim_get_current_buf()
api.nvim_buf_set_lines(unsaved, 0, -1, false, { "buffer only" })
view = tools.compare({ cwd = root })
wait(function()
  return view.current ~= nil
end)
assert(
  view.current.path == "b.txt" and text(view.windows[2]) == "buffer only",
  "File panel must include buffer-only changes"
)
view:close()
api.nvim_buf_delete(unsaved, { force = true })
git("checkout", "-qb", "side")
vim.fn.writefile({ "theirs" }, root .. "/a.txt")
git("add", "a.txt")
git("commit", "-qm", "side")
git("checkout", "-q", "main")
vim.fn.writefile({ "ours" }, root .. "/a.txt")
git("add", "a.txt")
git("commit", "-qm", "main")
assert(command("-c", "merge.conflictstyle=diff3", "merge", "side").code ~= 0)
tools.setup({ diff = { wrap = true }, buffer = false })
view = tools.merge({ cwd = root })
wait(function()
  return view.current ~= nil
end)
assert(#view.windows == 3 and text(view.windows[1]) == "ours" and text(view.windows[3]) == "theirs")
balanced()
assert(vim.wo[view.windows[2]].winbar:find("Result", 1, true))
for _, win in ipairs(view.windows) do
  assert(vim.wo[win].wrap, "Configured wrap applies to all merge panes")
end
vim.fn.maparg("<M-z>", "n", false, true).callback()
for _, win in ipairs(view.windows) do
  assert(not vim.wo[win].wrap, "Merge toggle updates all panes")
end
local conflict = require("git_tools.conflict")
assert(#conflict.blocks(api.nvim_buf_get_lines(view.result, 0, -1, false)) == 1)
local rejected
view:resolve(function(err)
  rejected = err
end)
assert(rejected and git("ls-files", "-u") ~= "", "Unresolved markers must block staging")
api.nvim_set_current_win(view.windows[2])
api.nvim_win_set_cursor(0, { 1, 0 })
assert(conflict.choose("both", view.result))
assert(text(view.windows[2]) == "ours\ntheirs")
assert(git("ls-files", "-u") ~= "", "Choosing text must not stage implicitly")
local done
view:resolve(function(err)
  assert(not err, err)
  done = true
end)
wait(function()
  return done
end)
assert(git("ls-files", "-u") == "" and git("show", ":a.txt") == "ours\ntheirs\n")
view:close()
vim.fn.delete(root, "rf")

local fixture = dofile((vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()) .. "/tests/helpers.lua").fixture()
vim.fn.mkdir(fixture.root .. "/lib/core", "p")
fixture:write("lib/core/a.txt", { "base" })
fixture:write("root.txt", { "base" })
fixture:git("add", ".")
fixture:git("commit", "-qm", "initial")
fixture:write("lib/core/a.txt", { "index" })
fixture:git("add", "lib/core/a.txt")
fixture:write("lib/core/a.txt", { "working" })
fixture:write("root.txt", { "changed" })
view = tools.compare({ cwd = fixture.root })
wait(function()
  return view.current ~= nil
end)
local function panel_lines()
  return api.nvim_buf_get_lines(view.panel, 0, -1, false)
end
assert(vim.deep_equal(panel_lines(), { "▾ lib", "  ▾ core", "     S  a.txt", "     W  a.txt", " W  root.txt" }))
assert(view.current.path == "lib/core/a.txt" and view.current.kind == "staged")
api.nvim_set_current_win(view.panel_win)
local open_row = vim.fn.maparg("<CR>", "n", false, true).callback
api.nvim_win_set_cursor(view.panel_win, { 1, 0 })
open_row()
assert(vim.deep_equal(panel_lines(), { "▸ lib", " W  root.txt" }))
assert(view.current.kind == "staged" and text(view.windows[2]) == "index", "Folding must preserve the displayed diff")
view:refresh()
wait(function()
  return view.current.path == "root.txt"
end)
assert(vim.deep_equal(panel_lines(), { "▸ lib", " W  root.txt" }), "Refresh must preserve collapsed directories")
api.nvim_set_current_win(view.panel_win)
api.nvim_win_set_cursor(view.panel_win, { 1, 0 })
open_row()
api.nvim_win_set_cursor(view.panel_win, { 4, 0 })
open_row()
wait(function()
  return view.current.path == "lib/core/a.txt" and view.current.kind == "unstaged"
end)
assert(text(view.windows[1]) == "index" and text(view.windows[2]) == "working")
assert(api.nvim_win_get_cursor(view.panel_win)[1] == 4, "Selection must follow the visible file row")
view:close()
fixture:cleanup()
print(
  "git views: staged/working and revision diffs, directory trees, root commits, unsaved buffers and three-way resolution passed"
)
vim.cmd("qa!")
