-- Optional end-to-end check against real LazyGit/Delta/bat in Neovim's PTY.
local root = vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root)
dofile(root .. "/tests/minimal_init.lua")
local theme_root = vim.fs.dirname(root) .. "/theme-tools.nvim"
if
  vim.fn.isdirectory(theme_root) == 0
  or vim.fn.executable("lazygit") ~= 1
  or vim.fn.executable("delta") ~= 1
  or vim.fn.executable("bat") ~= 1
then
  print("SKIP real LazyGit theme PTY (requires LazyGit, Delta, bat and sibling theme-tools)")
  vim.cmd("qa!")
  return
end
vim.opt.rtp:prepend(theme_root)
package.path = root .. "/tests/?.lua;" .. package.path
local f = require("helpers").fixture()
local themes, api = require("theme_tools"), vim.api
f:write("sample.lua", { 'local answer = "previous"', "return answer" })
f:git("add", "sample.lua")
f:git("commit", "-qm", "Initial")
f:write("sample.lua", { 'local answer = "updated"', "return answer" })
vim.fn.mkdir(f.root .. "/config", "p")
local base = f.root .. "/base.yml"
vim.fn.writefile({
  "disableStartupPopups: true",
  "update: {method: never}",
  "gui: {mouseEvents: false, showRandomTip: false}",
  "git:",
  "  diffRenderers:",
  "    - command: delta --dark --paging=never --line-numbers --hyperlinks",
  "      colorArg: always",
}, base)
local original = vim.fn.readfile(base)
local bat = vim.fn.exepath("bat")
vim.fn.mkdir(f.root .. "/bin", "p")
vim.fn.writefile({
  "#!/bin/sh",
  'if [ "$1" = cache ]; then',
  '  printf "build\\n" >> "$GIT_TOOLS_BAT_LOG"',
  '  while [ ! -f "$GIT_TOOLS_BAT_READY" ]; do sleep 0.01; done',
  "fi",
  "exec " .. vim.fn.shellescape(bat) .. ' "$@"',
}, f.root .. "/bin/bat")
assert(vim.uv.fs_chmod(f.root .. "/bin/bat", 448))
local bat_log, bat_ready = f.root .. "/bat.log", f.root .. "/bat.ready"
vim.o.columns, vim.o.lines, vim.o.termguicolors = 120, 40, true
vim.cmd.colorscheme("theme-tools-mocha")
themes.refresh_palette()
local source = api.nvim_get_current_buf()
api.nvim_buf_set_lines(source, 0, -1, false, { "unsaved source" })
local output, termopen = "", vim.fn.termopen
vim.fn.termopen = function(argv, opts)
  opts.on_stdout = function(_, data)
    output = output .. table.concat(data, "\n")
  end
  return termopen(argv, opts)
end
local open = require("git_tools").lazygit
local opts = {
  cwd = f.root,
  args = { "--debug" },
  env = {
    CONFIG_DIR = f.root .. "/config",
    LG_CONFIG_FILE = base,
    BAT_CONFIG_DIR = f.root .. "/bat-config",
    TERM = "xterm-256color",
    COLORTERM = "truecolor",
    NO_COLOR = "",
    GIT_CONFIG_GLOBAL = "/dev/null",
    GIT_CONFIG_NOSYSTEM = "1",
    PATH = f.root .. "/bin:" .. vim.env.PATH,
    GIT_TOOLS_BAT_LOG = bat_log,
    GIT_TOOLS_BAT_READY = bat_ready,
  },
}
local session = assert(open(opts))
assert(not session.theme.syntax_cache, "The cold launch must return without waiting for a build")
local function wait(predicate, message)
  if not vim.wait(10000, predicate, 10) then
    local diagnostics = "/tmp/git-tools-lazygit-theme-output.txt"
    vim.fn.writefile({ output:gsub("\27", "<ESC>") }, diagnostics)
    error(message .. "; terminal output: " .. diagnostics)
  end
  assert(not session.exited, "LazyGit exited unexpectedly: " .. output)
end
local function rgb(color, background)
  local r, g, b = color:match("#(%x%x)(%x%x)(%x%x)")
  return string.format("%d;2;%d;%d;%d", background and 48 or 38, tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
end
wait(function()
  return output:find("sample.lua", 1, true)
end, "LazyGit must render the repository")
local mocha = themes.palette()
assert(not session.theme.syntax_cache, "The first frame must render while bat is blocked")
wait(function()
  return output:find(rgb(mocha.ui.accent), 1, true)
end, "Initial UI must use Mocha's accent")
vim.fn.chansend(session.job, "2")
wait(function()
  return output:find("answer", 1, true)
end, "Real delta must render the file diff")
assert(output:find(rgb(mocha.git.add), 1, true), "Delta line numbers must use the semantic add color")
local job, buf = session.job, session.buf
assert(vim.fn.writefile({}, bat_ready) == 0)
wait(function()
  return session.theme.syntax_cache
end, "Delta must load the generated syntax theme after the first frame")
local initial_cache = session.theme.syntax_cache
output = ""
api.nvim_set_hl(0, "GitToolsTestString", { fg = "#01a2b3", italic = true })
api.nvim_set_hl(0, "@string", { link = "GitToolsTestString" })
api.nvim_set_hl(0, "@keyword", { fg = "#04c5d6" })
themes.refresh_palette()
assert(vim.deep_equal(mocha, themes.palette()), "The token-only change must leave the semantic palette equal")
wait(function()
  return output:find(rgb("#01a2b3"), 1, true) and output:find(rgb("#04c5d6"), 1, true)
end, "Delta must render mapped colors from a token-only change and follow highlight links")
local updated_cache = assert(session.theme.syntax_cache)
assert(updated_cache ~= initial_cache)
themes.refresh_palette()
assert(session.theme.syntax_cache == updated_cache, "Repeated publishes must reuse the same cache")

assert(vim.fn.delete(bat_ready) == 0)
local builds = #vim.fn.readfile(bat_log)
api.nvim_set_hl(0, "@string", { fg = "#0123de" })
themes.refresh_palette()
local stale = session.theme.syntax_key
wait(function()
  return #vim.fn.readfile(bat_log) > builds
end, "The superseded theme must start building")
vim.cmd.colorscheme("theme-tools-mocha")
themes.refresh_palette()
assert(session.theme.syntax_cache == initial_cache)
assert(vim.fn.writefile({}, bat_ready) == 0)
wait(function()
  return require("git_tools.lazygit.delta_syntax").cached(stale)
end, "The superseded build must finish")
assert(session.theme.syntax_cache == initial_cache, "A superseded build must not recolor the session")

output = ""
vim.cmd.colorscheme("theme-tools-dracula")
themes.refresh_palette()
local dracula = themes.palette()
local dracula_string = string.format("#%06x", api.nvim_get_hl(0, { name = "@string", link = false }).fg)
wait(function()
  return output:find(rgb(dracula.ui.accent), 1, true)
end, "Existing LazyGit must reload Dracula's UI colors on focus-in")
wait(function()
  return output:find(rgb(dracula.git.add), 1, true)
end, "Existing delta preview must reload Dracula's add color")
wait(function()
  return session.theme.syntax_cache and output:find(rgb(dracula_string), 1, true)
end, "Existing Delta preview must reload the generated Dracula string color")
assert(session.theme.syntax_cache and session.theme.syntax_cache ~= updated_cache)
assert(session.job == job and session.buf == buf, "Switching themes must preserve the session")
-- Exercise another live refresh with custom semantics, rather than theme names.
output = ""
require("theme_tools.palette").setup({ overrides = {
  ui = { accent = "#123456" },
  git = { add = "#abcdef" },
} })
themes.refresh_palette()
wait(function()
  return output:find(rgb("#123456"), 1, true) and output:find(rgb("#abcdef"), 1, true)
end, "Live palette overrides must reach both LazyGit and delta")
output = ""
require("theme_tools.palette").setup({})
vim.o.background = "light"
vim.cmd.colorscheme("default")
themes.refresh_palette()
local light = themes.palette()
wait(function()
  return session.theme.syntax_cache
    and output:find(rgb(light.ui.accent), 1, true)
    and output:find(rgb(light.git.add), 1, true)
end, "The live light palette and its generated syntax theme must reach LazyGit and Delta")
assert(session.job == job and session.buf == buf)
local theme_dir = session.theme.root
session:close()
assert(vim.fn.isdirectory(theme_dir) == 0)
assert(api.nvim_get_current_buf() == source and api.nvim_buf_get_lines(source, 0, -1, false)[1] == "unsaved source")
assert(vim.bo[source].modified and vim.deep_equal(vim.fn.readfile(base), original))
assert(vim.fn.isdirectory(initial_cache) == 1, "Closing LazyGit must keep the shared cache")
vim.o.background = "dark"
vim.cmd.colorscheme("theme-tools-mocha")
themes.refresh_palette()
builds = #vim.fn.readfile(bat_log)
output = ""
local reopened = assert(open(opts))
assert(reopened.theme.syntax_cache == initial_cache, "A new session must start with the cached theme")
wait(function()
  return output:find("sample.lua", 1, true)
end, "The warm launch must render the repository")
assert(not reopened.exited)
assert(#vim.fn.readfile(bat_log) == builds, "A warm launch must skip bat")
reopened:close()
vim.fn.termopen = termopen
assert(vim.v.errmsg == "", vim.v.errmsg)
if vim.env.GIT_TOOLS_THEME_TUI_RESULT then
  local lazy = package.loaded["lazy.core.config"]
  local plugin = lazy and lazy.plugins["git-tools.nvim"]
  vim.fn.writefile({
    vim.json.encode({
      passed = true,
      plugin_dir = plugin and plugin.dir or root,
      same_job = session.job == job,
      same_buffer = session.buf == buf,
    }),
  }, vim.env.GIT_TOOLS_THEME_TUI_RESULT)
end
f:cleanup()
print("Real LazyGit/Delta PTY: cold and warm launches, live token colors, stale builds and cleanup passed")
vim.cmd("qa!")
