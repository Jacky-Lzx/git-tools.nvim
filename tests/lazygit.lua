vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local api, tools = vim.api, require("git_tools")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local command, record = root .. "/fake lazygit", root .. "/record"
vim.fn.writefile({
  "#!/bin/sh",
  'printf "%s\\n" "$PWD" "$@" > "$GIT_TOOLS_LAZYGIT_RECORD"',
  "printf 'fake-lazygit-ready\\n'",
  "while IFS= read -r key; do",
  'case "$key" in quit) exit 0;; fail) exit 7;; size) stty size > "$GIT_TOOLS_LAZYGIT_RECORD.size";; esac',
  "done",
}, command)
assert(vim.uv.fs_chmod(command, 493))
local function wait(test, message)
  assert(vim.wait(5000, test, 5), message or "Terminal timeout")
end
local messages, notify = {}, vim.notify
vim.notify = function(message)
  messages[#messages + 1] = message
end
local origin, source = api.nvim_get_current_win(), api.nvim_get_current_buf()
api.nvim_buf_set_lines(source, 0, -1, false, { "unsaved source" })
local opts = {
  command = command,
  cwd = root,
  env = { GIT_TOOLS_LAZYGIT_RECORD = record },
  args = { "space arg", "$(touch INJECTED)" },
}
local session = assert(tools.lazygit(opts))
wait(function()
  return vim.fn.filereadable(record) == 1
end)
local lines = vim.fn.readfile(record)
assert(lines[1] == root and lines[2] == opts.args[1] and lines[3] == opts.args[2])
assert(vim.fn.filereadable(root .. "/INJECTED") == 0 and vim.env.GIT_TOOLS_LAZYGIT_RECORD == nil)
assert(vim.bo[session.buf].buftype == "terminal" and api.nvim_win_get_config(session.win).relative == "editor")
assert(tools.lazygit(opts) == session, "Repeated launch must focus the existing job")
vim.o.columns, vim.o.lines = 100, 32
api.nvim_exec_autocmds("VimResized", {})
assert(
  api.nvim_win_get_width(session.win) == math.floor(98 * 0.9)
    and api.nvim_win_get_height(session.win) == math.floor(28 * 0.9)
)
vim.fn.chansend(session.job, "size\n")
wait(function()
  return vim.fn.filereadable(record .. ".size") == 1
end)
local rows, cols = vim.fn.readfile(record .. ".size")[1]:match("(%d+)%s+(%d+)")
assert(
  tonumber(rows) == api.nvim_win_get_height(session.win) and tonumber(cols) == api.nvim_win_get_width(session.win),
  "PTY must resize with the float"
)
vim.fn.chansend(session.job, "quit\n")
wait(function()
  return session.closed
end)
assert(not api.nvim_buf_is_valid(session.buf) and not api.nvim_win_is_valid(session.win))
assert(api.nvim_get_current_win() == origin and api.nvim_get_current_buf() == source)
assert(api.nvim_buf_get_lines(source, 0, -1, false)[1] == "unsaved source" and vim.bo[source].modified)
session = assert(tools.lazygit(opts))
local job = session.job
api.nvim_win_close(session.win, true)
wait(function()
  return session.closed and vim.fn.jobwait({ job }, 0)[1] ~= -1
end)
assert(not api.nvim_buf_is_valid(session.buf), "Manual float close must stop the child and free its buffer")
session = assert(tools.lazygit(opts))
vim.fn.chansend(session.job, "fail\n")
wait(function()
  return session.exited
end)
assert(not session.closed and api.nvim_buf_is_valid(session.buf) and #messages == 1)
assert(tools.lazygit(opts) == session, "Failed output must remain inspectable")
session:close()
local missing = tools.lazygit({ command = root .. "/missing" })
assert(not missing and #messages == 2 and not require("git_tools.lazygit").current)
vim.notify = notify
assert(vim.v.errmsg == "", vim.v.errmsg)
assert(not package.loaded.snacks and not package.loaded.selection_tools)
vim.fn.delete(root, "rf")
print(
  "git lazygit: real terminal job, literal args/cwd, resize, exit, close, repeat, failure output and source preservation passed"
)
vim.cmd("qa!")
