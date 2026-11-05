vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api = vim.api
local h, buffer, tools = require("git_tools.hunks"), require("git_tools.buffer"), require("git_tools")
for _, pair in ipairs({
  { "a\nb\nc\n", "a\nx\ny\nc\n" },
  { "a\nb\n", "b\n" },
  { "a\n", "a" },
  { "", "new\n" },
  { "a", "" },
}) do
  local old, new = h.text(pair[1]), h.text(pair[2])
  local changes = h.diff(old, new)
  assert(h.project(old, new, changes, nil, false).text == new.text)
  assert(h.project(old, new, changes, nil, true).text == old.text)
end
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local function git(...)
  local args = { "git", "-C", root, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null" }
  vim.list_extend(args, { ... })
  local result = vim.system(args):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
git("init", "-q")
git("config", "user.name", "Fixture")
git("config", "user.email", "fixture@example.invalid")
git("config", "core.autocrlf", "false")
local path = root .. "/space \t\n中.txt"
vim.fn.writefile({ "one", "two", "three", "four", "five" }, path)
git("add", ".")
git("commit", "-qm", "initial")
vim.cmd.edit(vim.fn.fnameescape(path))
local buf = api.nvim_get_current_buf()
tools.setup({ buffer = { debounce = 10, word_diff = true } })
local function ready()
  local done, state
  buffer.ready(buf, function(err, s)
    assert(not err, err)
    state = s
    done = true
  end)
  assert(
    vim.wait(5000, function()
      return done
    end, 5),
    "Buffer refresh timeout"
  )
  return state
end
local function action(name, opts)
  local done
  opts = vim.tbl_extend("force", opts or {}, {
    buf = buf,
    callback = function(err)
      assert(not err, err)
      done = true
    end,
  })
  tools[name](opts)
  assert(
    vim.wait(5000, function()
      return done
    end, 5),
    name .. " timeout"
  )
end
api.nvim_buf_set_lines(buf, 0, 2, false, { "ONE", "TWO" })
local state = ready()
assert(#state.hunks == 1 and state.summary.changed == 2)
action("stage_hunk", { range = { 2, 2 } })
assert(
  git("show", ":" .. vim.fs.basename(path)) == "one\nTWO\nthree\nfour\nfive\n",
  "Visual staging must include only selected replacement"
)
assert(vim.fn.readfile(path)[2] == "two", "Staging unsaved content must not save disk")
action("unstage_hunk", { range = { 2, 2 } })
assert(git("show", ":" .. vim.fs.basename(path)) == "one\ntwo\nthree\nfour\nfive\n")
action("reset_hunk", { range = { 1, 1 } })
assert(api.nvim_buf_get_lines(buf, 0, 2, false)[1] == "one" and api.nvim_buf_get_lines(buf, 0, 2, false)[2] == "TWO")
action("stage_buffer")
assert(git("show", ":" .. vim.fs.basename(path)):find("TWO", 1, true))
action("unstage_buffer")
action("reset_buffer")
assert(#ready().hunks == 0)
api.nvim_buf_set_lines(buf, 1, 1, false, { "added 1", "added 2" })
action("stage_hunk", { range = { 3, 3 } })
assert(git("show", ":" .. vim.fs.basename(path)) == "one\nadded 2\ntwo\nthree\nfour\nfive\n")
action("unstage_buffer")
action("reset_buffer")
api.nvim_buf_set_lines(buf, 0, 1, false, {})
action("stage_buffer")
assert(git("show", ":" .. vim.fs.basename(path)) == "two\nthree\nfour\nfive\n")
action("unstage_buffer")
action("reset_buffer")
vim.bo[buf].endofline = false
action("stage_buffer")
assert(git("show", ":" .. vim.fs.basename(path)):sub(-1) ~= "\n", "Final newline must be staged exactly")
action("unstage_buffer")
action("reset_buffer")
tools.toggle_overlay(buf)
assert(vim.wait(5000, function()
  return buffer.states[buf].overlay
end, 5))
api.nvim_buf_set_lines(buf, 0, 1, false, { "overlay" })
assert(
  vim.wait(5000, function()
    return #api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsOverlay"), 0, -1, {}) > 0
  end, 5),
  "Overlay must refresh after typing"
)
local lazy = vim.fn.stdpath("data") .. "/lazy/"
local status = require("git_tools.integrations.status")
if vim.fn.isdirectory(lazy .. "lualine.nvim") == 1 then
  vim.opt.rtp:append(lazy .. "lualine.nvim")
  require("lualine").setup({
    options = { theme = "auto", icons_enabled = false },
    sections = {
      lualine_a = { status.branch },
      lualine_b = { { "diff", source = status.diff, symbols = { added = "+", modified = "~", removed = "-" } } },
    },
  })
  vim.g.actual_curwin = api.nvim_get_current_win()
  require("lualine").refresh({ force = true })
  local rendered = require("lualine").statusline()
  assert(rendered:find("~1", 1, true), "Actual lualine must render the GitTools source: " .. rendered)
end
if vim.fn.isdirectory(lazy .. "nvim-scrollbar") == 1 then
  vim.opt.rtp:append(lazy .. "nvim-scrollbar")
  require("scrollbar").setup({ handlers = { gitsigns = false }, handle = { hide_if_all_visible = false } })
  assert(status.scrollbar() and status.scrollbar())
  require("scrollbar.handlers").show()
  local marks = require("scrollbar.utils").get_scrollbar_marks(buf).git_tools
  assert(#marks == 1 and marks[1].type == "GitChange", "Actual scrollbar must receive GitTools hunk marks")
end
vim.fn.writefile({ "external" }, path)
git("add", "--", vim.fs.basename(path))
assert(
  vim.wait(5000, function()
    return buffer.states[buf].index.text == "external\n"
  end, 5),
  "External staging must refresh hunks"
)
buffer.detach(buf)
assert(#api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("GitToolsSigns"), 0, -1, {}) == 0)
vim.cmd.enew({ bang = true })
vim.cmd.edit(root .. "/new.txt")
buf = api.nvim_get_current_buf()
api.nvim_buf_set_lines(buf, 0, -1, false, { "new unsaved" })
action("stage_buffer")
assert(git("show", ":new.txt") == "new unsaved\n")
action("unstage_buffer")
assert(git("ls-files", "--", "new.txt") == "")
buffer.detach(buf)
vim.cmd.enew({ bang = true })
vim.fn.writefile({ "a\r", "b\r" }, root .. "/crlf.txt")
git("add", "crlf.txt")
git("update-index", "--chmod=+x", "--", "crlf.txt")
vim.cmd.edit(root .. "/crlf.txt")
buf = api.nvim_get_current_buf()
assert(vim.bo[buf].fileformat == "dos" and #ready().hunks == 0)
api.nvim_buf_set_lines(buf, 0, 1, false, { "changed" })
local source_win = api.nvim_get_current_win()
require("git_tools.actions").preview({ buf = buf })
assert(vim.wait(5000, function()
  return api.nvim_get_current_win() ~= source_win
end, 5))
local preview_buf = api.nvim_get_current_buf()
assert(vim.b[preview_buf].git_tools_diff and not vim.bo[preview_buf].modifiable)
assert(api.nvim_buf_get_lines(preview_buf, 0, -1, false)[1]:find("crlf.txt", 1, true))
api.nvim_win_close(0, true)
assert(not api.nvim_buf_is_valid(preview_buf) and api.nvim_get_current_win() == source_win)
action("stage_buffer")
assert(git("show", ":crlf.txt") == "changed\r\nb\r\n", "CRLF index bytes must be retained")
assert(git("ls-files", "--stage", "--", "crlf.txt"):match("^100755"), "Staging must retain executable mode")
buffer.detach(buf)
vim.cmd.enew({ bang = true })
vim.cmd.edit(root .. "/empty.txt")
buf = api.nvim_get_current_buf()
action("stage_buffer")
assert(git("show", ":empty.txt") == "", "An empty buffer must stage zero bytes")
action("unstage_buffer")
assert(git("ls-files", "--", "empty.txt") == "", "An empty added file must unstage")
buffer.detach(buf)
vim.fn.delete(root, "rf")
print("git hunks: partial stage/unstage/reset, unsaved buffers, newlines, overlay and external index refresh passed")
vim.cmd("qa!")
