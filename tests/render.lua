vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local render = require("git_tools.diff")
local count = 0
local function check(value, label)
  assert(value, label)
  count = count + 1
end
local ctx = { win = vim.api.nvim_get_current_win(), preview = {}, item = { root = "/tmp/project" } }
local resets, terminal, sent, system_calls = 0, 0, "", 0
function ctx.preview:reset()
  resets = resets + 1
end
function ctx.preview:set_title(title)
  self.title = title
end
function ctx.preview:set_lines(lines)
  self.lines = lines
end
function ctx.preview:highlight() end
local adopted, prepared
ctx.is_cancelled = function()
  return false
end
ctx.set_lines = function(lines, ft, title)
  ctx.preview:set_lines(lines)
  ctx.preview:set_title(title)
end
ctx.set_buffer = function(buf, metadata)
  check(buf == prepared and sent ~= "", "only prepared ANSI frames are adopted")
  check(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= "", "blank frames are never published")
  adopted = buf
  ctx.preview:set_title(metadata.title)
  return true
end
local args, process_opts, complete, process
vim.api.nvim_open_term = function(buf)
  check(buf ~= adopted, "ANSI rendering prepares a buffer before adopting it")
  prepared = buf
  terminal = terminal + 1
  return 100
end
vim.api.nvim_chan_send = function(channel, text)
  check(channel == 100, "ANSI output goes to renderer channel")
  sent = text
  vim.api.nvim_buf_set_lines(prepared, 0, -1, false, { "rendered ANSI text" })
end
local available = true
vim.fn.executable = function()
  return available and 1 or 0
end
vim.system = function(argv, opts, callback)
  system_calls = system_calls + 1
  args, process_opts, complete = argv, opts, callback
  process = { closed = false, killed = false }
  function process:is_closing()
    return self.closed
  end
  function process:kill(signal)
    self.killed = signal
  end
  return process
end
local config =
  { cwd = "/tmp/project", backend = "delta", delta = { command = "delta", args = { "--line-numbers" }, timeout = 500 } }
local lines = { "--- file:///tmp/a.lua", "+++ file:///tmp/a.lua", "@@ -1 +1 @@", "-old", "+new" }
local valid = true
local function start()
  return render.render(ctx, lines, config, function()
    return valid
  end)
end
local function flush()
  vim.wait(5, function()
    return false
  end, 1)
end
local stop = start()
check(args[1] == "delta" and vim.tbl_contains(args, "--line-numbers"), "executable and extra arguments")
check(
  vim.tbl_contains(args, "--paging=never") and vim.tbl_contains(args, "--true-color=always"),
  "non-interactive true color"
)
check(vim.tbl_contains(args, "--width=" .. vim.api.nvim_win_get_width(ctx.win)), "preview window width")
check(process_opts.stdin == table.concat(lines, "\n") .. "\n", "diff is passed through stdin")
check(process_opts.timeout == 500, "bounded asynchronous process")
check(process_opts.cwd == ctx.item.root, "delta runs from the root used in display labels")
complete({ code = 0, stdout = "\27[31mcolored\27[0m\n" })
flush()
check(terminal == 1 and sent:find("\27[31m", 1, true), "successful output keeps ANSI colors")
process.closed = true
stop:close()
check(not process.killed, "completed process is not killed")

for _, output in ipairs({
  { code = 2, stdout = "bad" },
  { code = 124, stdout = "" },
  { code = 0, stdout = "" },
}) do
  start()
  complete(output)
  flush()
  check(vim.deep_equal(ctx.preview.lines, lines), "failure, timeout or empty output falls back")
end
local before = system_calls
available = false
start()
check(
  system_calls == before and vim.deep_equal(ctx.preview.lines, lines),
  "missing executable falls back without spawning"
)
available = true
config.backend = "vim"
start()
check(system_calls == before, "native backend does not invoke delta")
config.backend = "delta"
render.render(ctx, { "Create file: file:///tmp/new.lua" }, config, function()
  return true
end)
check(system_calls == before, "resource-only preview bypasses delta")
render.render(ctx, { "No text edit to preview." }, config, function()
  return true
end)
check(system_calls == before, "command-only preview bypasses delta")

stop = start()
local stale = complete
local previous_terminal = terminal
valid = false
stale({ code = 0, stdout = "late" })
flush()
check(terminal == previous_terminal, "late previous-item output is ignored")
stop:close()
check(process.killed == 15, "selection change cancels process")
valid = true
stop = start()
stale = complete
stop:close()
stale({ code = 0, stdout = "closed" })
flush()
check(terminal == previous_terminal, "late cancelled output is ignored")
local system = vim.system
vim.system = function()
  error("spawn failed")
end
start()
check(vim.deep_equal(ctx.preview.lines, lines), "spawn errors fall back")
vim.system = system
config.delta.args = { "--light", "--line-numbers", "literal `value` $(value)" }
start()
check(not vim.tbl_contains(args, "--dark") and vim.tbl_contains(args, "--light"), "explicit light/dark is respected")
check(args[#args] == "literal `value` $(value)", "arguments are literal argv entries")
local handle = start()
local stale_resize = complete
handle:resize()
local rendered_before = terminal
stale_resize({ code = 0, stdout = "old width" })
flush()
check(terminal == rendered_before, "resize discards output from the old render generation")
complete({ code = 0, stdout = "new width" })
flush()
check(terminal == rendered_before + 1, "resize publishes the current generation")
handle:close()

local write_terminal = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function() end
local windows, previous = #vim.api.nvim_list_wins(), adopted
handle = start()
complete({ code = 0, stdout = "pending ANSI" })
flush()
local pending_buf = prepared
check(adopted == previous and vim.api.nvim_buf_is_valid(pending_buf), "pending terminal keeps the previous frame")
check(#vim.api.nvim_list_wins() == windows + 1, "terminal preparation uses one hidden window")
handle:close()
check(not vim.api.nvim_buf_is_valid(pending_buf), "cancellation deletes the unadopted frame")
check(#vim.api.nvim_list_wins() == windows, "cancellation closes the hidden window")

handle = start()
complete({ code = 0, stdout = "old width pending ANSI" })
flush()
pending_buf = prepared
handle:resize()
check(not vim.api.nvim_buf_is_valid(pending_buf), "resize discards pending terminal preparation")
vim.api.nvim_chan_send = write_terminal
complete({ code = 0, stdout = "ready resized ANSI" })
flush()
check(
  adopted == prepared and #vim.api.nvim_list_wins() == windows,
  "ready resized frame publishes without leaking windows"
)
handle:close()

vim.api.nvim_chan_send = function() end
config.delta.timeout = 10
handle = start()
complete({ code = 0, stdout = "never reaches the terminal" })
flush()
pending_buf = prepared
check(
  vim.wait(100, function()
    return not vim.api.nvim_buf_is_valid(pending_buf)
  end, 1),
  "unready terminal preparation has a bounded timeout"
)
check(
  #vim.api.nvim_list_wins() == windows and vim.deep_equal(ctx.preview.lines, lines),
  "preparation timeout cleans up and falls back"
)
handle:close()
vim.api.nvim_chan_send = write_terminal
print(("git-tools render: %d assertions passed"):format(count))
vim.cmd("qa!")
