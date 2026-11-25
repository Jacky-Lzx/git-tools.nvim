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
vim.fn.writefile({ "other" }, root .. "/README.md")
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
assert(not vim.bo[view.panel].buflisted, "The Compare file panel must be unlisted")
assert(not vim.wo[view.panel_win].number and not vim.wo[view.panel_win].relativenumber)
assert(vim.wo[view.windows[2]].winbar:find("Index", 1, true))
assert(api.nvim_buf_get_lines(view.panel, 0, 1, false)[1] == " S  a.txt")
for _, win in ipairs(view.windows) do
  assert(vim.wo[win].winhighlight:find("DiffAdd:GitToolsDiffAdd", 1, true), "Use subtle pane-local diff colors")
  assert(vim.wo[win].cursorlineopt == "number", "Diff panes must avoid CursorLine underlining the text area")
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
local snapshot = api.nvim_win_get_buf(view.windows[1])
local actual = view.result
api.nvim_buf_set_lines(actual, 0, -1, false, { "unsaved" })
view:close()
assert(not api.nvim_buf_is_valid(snapshot), "Closing diff must wipe the temporary snapshot")
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
vim.cmd.edit(root .. "/README.md")
local editor = api.nvim_get_current_win()
local editor_highlights = vim.wo[editor].winhighlight
local unsaved = api.nvim_get_current_buf()
api.nvim_buf_set_lines(unsaved, 0, -1, false, { "buffer only" })
view = tools.compare({ cwd = root })
wait(function()
  return view.current ~= nil
end)
assert(
  view.current.path == "README.md" and text(view.windows[2]) == "buffer only",
  "File panel must include buffer-only changes"
)
local working_pane = view.windows[2]
assert(api.nvim_win_get_buf(working_pane) == unsaved, "Compare must reuse the open Markdown buffer")
assert(
  vim.wo[working_pane].winhighlight:find("DiffAdd:GitToolsDiffAdd", 1, true),
  "The working-tree pane must retain subtle diff colors after switching to an open file"
)
assert(vim.wo[editor].winhighlight == editor_highlights, "Compare must preserve the original editor window's colors")
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
tools.setup({
  buffer = false,
  compare = {
    keymap = {
      panel = {
        Q = "close",
        o = {
          function(ctx)
            assert(ctx.root == fixture.root and api.nvim_win_get_buf(ctx.win) == ctx.buf)
            if ctx.row.kind == "directory" then
              assert(ctx.row.item == nil and ctx.row.path == "lib")
              assert(ctx.current.path == "lib/core/a.txt" or ctx.current.path == "root.txt")
              return ctx.run("open")
            end
            assert(ctx.row.item.kind == "unstaged")
            ctx.row.item.path = "Changed in the callback"
          end,
          "open",
          function()
            error("A handled action must stop the binding")
          end,
          desc = "open or fold",
        },
        ["<C-n>"] = "next_file",
        ["%"] = "refresh",
        y = function(ctx)
          vim.fn.setreg('"', ctx.row.path)
          return true
        end,
      },
    },
  },
})
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
local function panel_mapping(lhs)
  return vim.fn.maparg(lhs, "n", false, true)
end
for _, lhs in ipairs({ "q", "<CR>", "<Tab>", "R" }) do
  assert(panel_mapping(lhs).buffer ~= 1, "Custom panel keys must replace defaults")
end
local function panel_footer()
  local win = view.panel_win
  return api.nvim_eval_statusline(vim.wo[win].statusline, {
    winid = win,
    maxwidth = api.nvim_win_get_width(win),
  }).str
end
local panel_width = api.nvim_win_get_width(view.panel_win)
local narrow = panel_footer()
assert(vim.startswith(narrow, " o: open or fold") and not narrow:find("3 files", 1, true))
api.nvim_win_set_width(view.panel_win, 100)
api.nvim_exec_autocmds("WinResized", {})
local wide = panel_footer()
assert(vim.startswith(wide, " o: open or fold  <C-n>: next  %: refresh  Q: close  y: custom action"))
assert(vim.endswith(wide, "3 files"))
api.nvim_win_set_width(view.panel_win, panel_width)
api.nvim_exec_autocmds("WinResized", {})
assert(panel_mapping("o").desc == "open or fold")
local open_row = panel_mapping("o").callback
api.nvim_win_set_cursor(view.panel_win, { 1, 0 })
open_row()
assert(vim.deep_equal(panel_lines(), { "▸ lib", " W  root.txt" }))
assert(view.current.kind == "staged" and text(view.windows[2]) == "index", "Folding must preserve the displayed diff")
panel_mapping("%").callback()
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
api.nvim_set_current_win(view.panel_win)
api.nvim_feedkeys("y", "xt", false)
assert(vim.fn.getreg('"') == "lib/core/a.txt", "A standalone callback must receive the cursor row")
panel_mapping("<C-n>").callback()
wait(function()
  return view.current.path == "root.txt"
end)
fixture:write("extra.txt", { "extra" })
panel_mapping("%").callback()
wait(function()
  return #view.items == 4 and view.panel_items == view.items
end)
api.nvim_win_set_width(view.panel_win, 100)
api.nvim_exec_autocmds("WinResized", {})
assert(vim.endswith(panel_footer(), "4 files"), "Refreshing the file list must update the footer")
vim.fn.delete(fixture.root .. "/extra.txt")
api.nvim_set_current_win(view.panel_win)
panel_mapping("Q").callback()
assert(view.closed, "Configured close key must close the view")

tools.setup({ buffer = false, compare = { panel_keys = { close = "Q", refresh = false } } })
view = tools.compare({ cwd = fixture.root, from = "HEAD", to = "HEAD" })
wait(function()
  return view.panel ~= nil
end)
assert(panel_mapping("R").buffer ~= 1, "A false key must disable the mapping")
assert(panel_mapping("<CR>").buffer == 1, "Omitted keys must keep their defaults")
assert(vim.deep_equal(panel_lines(), { "No changed files. Q: close" }), "Empty panel must omit disabled shortcuts")
view:close()

local no_next = false
tools.setup({
  buffer = false,
  compare = {
    keymap = {
      panel = {
        n = {
          "next_file",
          function(ctx)
            assert(not ctx.row and not ctx.current)
            no_next = true
            return true
          end,
        },
        q = false,
      },
    },
  },
})
view = tools.compare({ cwd = fixture.root, from = "HEAD", to = "HEAD" })
wait(function()
  return view.panel ~= nil
end)
panel_mapping("n").callback()
assert(no_next, "No available file must fall through to the next action")
assert(panel_mapping("q").buffer ~= 1 and panel_mapping("R").buffer ~= 1)
tools.setup({ buffer = false, compare = { keymap = { panel = {} }, panel_keys = { close = "Q" } } })
assert(panel_mapping("n").buffer == 1, "An open view must keep its mappings after repeated setup")
view:close()

view = tools.compare({ cwd = fixture.root, from = "HEAD", to = "HEAD" })
wait(function()
  return view.panel ~= nil
end)
assert(#api.nvim_buf_get_keymap(view.panel, "n") == 0, "An empty panel keymap must replace legacy and default mappings")
tools._dispose()
view = tools.compare({ cwd = fixture.root, from = "HEAD", to = "HEAD" })
wait(function()
  return view.panel ~= nil
end)
assert(panel_mapping("R").buffer == 1 and panel_mapping("q").buffer == 1, "Disposing must reset panel shortcuts")
view:close()

vim.cmd.tabnew()
local origin = api.nvim_get_current_tabpage()
local editor_win = api.nvim_get_current_win()
vim.wo[editor_win].signcolumn = "yes:2"
local first = tools.compare({ cwd = fixture.root, from = "HEAD", to = "HEAD" })
wait(function()
  return first.tab ~= nil
end)
local second = tools.compare({ cwd = fixture.root, from = "HEAD", to = "HEAD" })
wait(function()
  return second.tab ~= nil
end)
assert(tools.close_compares())
assert(
  first.closed
    and second.closed
    and not api.nvim_tabpage_is_valid(first.tab)
    and not api.nvim_tabpage_is_valid(second.tab)
)
assert(api.nvim_get_current_tabpage() == origin and api.nvim_get_current_win() == editor_win)
assert(vim.wo[editor_win].signcolumn == "yes:2")

view = tools.compare({ cwd = fixture.root, from = "HEAD", to = "HEAD" })
wait(function()
  return view.tab ~= nil
end)
vim.cmd.tabonly()
local closed, close_err = tools.close_compares()
assert(not closed and close_err and view:alive(), "The last Compare tab must block session capture")
vim.cmd.tabnew()
local fallback = api.nvim_get_current_tabpage()
api.nvim_set_current_tabpage(view.tab)
assert(tools.close_compares())
assert(view.closed and api.nvim_get_current_tabpage() == fallback)

fixture:cleanup()
print(
  "git views: staged/working and revision diffs, directory trees, root commits, unsaved buffers and three-way resolution passed"
)
vim.cmd("qa!")
