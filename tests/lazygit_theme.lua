local root = vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local theme_root = vim.fs.dirname(root) .. "/theme-tools.nvim"
if vim.fn.isdirectory(theme_root) == 0 then
  print("SKIP optional LazyGit theme-tools integration (sibling checkout not installed)")
  vim.cmd("qa!")
  return
end
vim.opt.rtp:prepend(theme_root)
local themes, adapter = require("theme_tools"), require("git_tools.lazygit_theme")
local api, uv = vim.api, vim.uv
local dir = vim.fn.tempname() .. " space ' $(touch INJECTED)"
vim.fn.mkdir(dir, "p")
dir = uv.fs_realpath(dir)
local base, extra, record = dir .. "/base.yml", dir .. "/extra.yml", dir .. "/record"
vim.fn.writefile({ "gui:", "  mouseEvents: true" }, base)
vim.fn.writefile({ "gui:", "  scrollHeight: 7" }, extra)
local original = vim.fn.readfile(base)
local command = dir .. "/lazygit"
vim.fn.writefile({
  "#!/bin/sh",
  'if [ "$1" = --print-config-dir ]; then printf "%s\\n" "$CONFIG_DIR"; exit; fi',
  'printf "%s\\n" "$LG_CONFIG_FILE" "$PATH" "$@" > "$RECORD"',
  "while IFS= read -r key; do :; done",
}, command)
assert(uv.fs_chmod(command, 493))
vim.fn.writefile({
  "#!/bin/sh",
  'if [ "$1" = --list-syntax-themes ]; then printf "dark\\tDracula\\ndark\\tCatppuccin Mocha\\ndark\\tansi\\n"; exit; fi',
  'printf "%s\\n" "$@"',
}, dir .. "/delta")
assert(uv.fs_chmod(dir .. "/delta", 493))
local env = { LG_CONFIG_FILE = base, CONFIG_DIR = dir, RECORD = record, PATH = dir .. ":" .. vim.env.PATH }
local opts = { command = command, args = {}, env = env, cwd = dir }
vim.cmd.colorscheme("theme-tools-mocha")
themes.refresh_palette()
assert(not adapter.prepare(vim.tbl_extend("force", opts, { theme = false })))
package.loaded.theme_tools = nil
assert(not adapter.prepare(opts) and not package.loaded.theme_tools, "Theming must not load an absent provider")
package.loaded.theme_tools = themes

local tools = require("git_tools")
local session = assert(tools.lazygit(opts))
assert(session.theme, "Loaded theme-tools must enable automatic theming")
assert(vim.wait(5000, function()
  return vim.fn.filereadable(record) == 1
end, 5))
local entries = vim.fn.readfile(record)
assert(entries[1] == base .. "," .. session.theme.path)
assert(entries[2] == session.theme.root .. ":" .. env.PATH)
assert(env.LG_CONFIG_FILE == base and #opts.args == 0, "Caller options must remain unchanged")
local function generated(state)
  return vim.json.decode(table.concat(vim.fn.readfile(state.path), "\n")).gui
end
local gui = generated(session.theme)
assert(gui.theme.activeBorderColor[1] == themes.palette().ui.accent)
assert(vim.deep_equal(gui.darkTheme, gui.theme) and vim.deep_equal(gui.lightTheme, gui.theme))
local function delta(state, args)
  local argv = { state.root .. "/delta" }
  vim.list_extend(argv, args or {})
  local result = vim.system(argv, { cwd = dir, env = state.env, text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.split(vim.trim(result.stdout), "\n", { plain = true })
end
local arguments = delta(session.theme, {
  "--plus-style",
  "old style",
  "--syntax-theme=Old",
  "--hyperlinks",
  "space arg",
  "$(touch INJECTED)",
  "--",
  "--plus-style=literal filename",
})
assert(vim.tbl_contains(arguments, "--syntax-theme=Catppuccin Mocha"))
assert(not vim.tbl_contains(arguments, "old style") and not vim.tbl_contains(arguments, "--syntax-theme=Old"))
assert(vim.tbl_contains(arguments, "--hyperlinks") and vim.tbl_contains(arguments, "space arg"))
assert(vim.tbl_contains(arguments, "$(touch INJECTED)"))
assert(arguments[#arguments] == "--plus-style=literal filename", "Arguments after -- must remain literal")
assert(vim.fn.filereadable(dir .. "/INJECTED") == 0)
local job, buf, theme_dir = session.job, session.buf, session.theme.root
vim.cmd.colorscheme("theme-tools-dracula")
themes.refresh_palette()
assert(session.job == job and session.buf == buf and not session.closed)
assert(generated(session.theme).theme.unstagedChangesColor[1] == themes.palette().git.delete)
assert(vim.tbl_contains(delta(session.theme), "--syntax-theme=Dracula"))
require("theme_tools.palette").setup({
  overrides = {
    ui = { accent = "#123456", selection_bg = "NONE", cursorline_bg = "NONE" },
    git = { add = "#abcdef" },
  },
})
themes.refresh_palette()
gui = generated(session.theme)
assert(gui.theme.activeBorderColor[1] == "#123456" and gui.theme.selectedLineBgColor[1] == "default")
assert(gui.theme.inactiveViewSelectedLineBgColor[1] == "default")
assert(vim.tbl_contains(delta(session.theme), "--line-numbers-plus-style=#abcdef"))
session:close()
assert(vim.fn.isdirectory(theme_dir) == 0, "Closing must remove scripts/config and unsubscribe")
themes.refresh_palette()
assert(vim.fn.isdirectory(theme_dir) == 0)
assert(vim.deep_equal(vim.fn.readfile(base), original))

local disabled = assert(tools.lazygit(vim.tbl_extend("force", opts, { theme = false })))
assert(not disabled.theme, "Per-call opt-out must keep the original launch path")
disabled:close()

-- CLI file lists take precedence over LG_CONFIG_FILE; unrelated args survive.
for _, args in ipairs({
  { "-ucf", base .. "," .. extra, "log" },
  { "--use-config-file=" .. base .. "," .. extra, "log" },
}) do
  local state = assert(adapter.prepare(vim.tbl_extend("force", opts, { args = args })))
  assert(state.files == base .. "," .. extra and vim.deep_equal(state.args, { "log" }))
  state:close()
end
-- An explicit config directory must be honored, including a missing default.
local defaults = vim.tbl_extend("force", opts, {
  args = { "--use-config-dir=" .. dir, "--", "--use-config-file=literal" },
  env = vim.tbl_extend("force", env, { LG_CONFIG_FILE = "" }),
})
local state = assert(adapter.prepare(defaults))
assert(state.files == "" and state.env.LG_CONFIG_FILE == state.path)
assert(vim.deep_equal(state.args, { "--use-config-dir", dir, "--", "--use-config-file=literal" }))
state:close()
vim.fn.writefile(original, dir .. "/config.yml")
state = assert(adapter.prepare(defaults))
assert(state.files == dir .. "/config.yml")
state:close()
local messages, notify = {}, vim.notify
vim.notify = function(message)
  messages[#messages + 1] = message
end
assert(not adapter.prepare(vim.tbl_extend("force", opts, { args = { "--use-config-file" } })))
assert(#messages == 1 and messages[1]:find("Missing value", 1, true), "Preparation errors must warn and fall back")
vim.notify = notify
require("theme_tools.palette").setup({})
assert(vim.v.errmsg == "", vim.v.errmsg)
vim.fn.delete(dir, "rf")
print(
  "LazyGit themes: live Mocha/Dracula and semantic overrides, config precedence, literal argv, delta and cleanup passed"
)
vim.cmd("qa!")
