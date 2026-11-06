-- Requiring the plugin installs no mappings, commands, UI or Git processes.
local M = { diff = require("git_tools.diff") }

function M.lazygit(opts)
  return require("git_tools.lazygit").open(opts)
end

function M.compare(opts)
  return require("git_tools.view").open(opts)
end
function M.toggle_compare(opts)
  return require("git_tools.view").toggle(opts)
end
function M.diffthis(revision)
  return M.compare({ path = vim.api.nvim_buf_get_name(0), from = revision, include_unchanged = true })
end
function M.merge(opts)
  return M.compare(vim.tbl_extend("force", {}, opts or {}, { merge = true }))
end

function M.setup(opts)
  assert(opts == nil or type(opts) == "table", "git-tools.nvim: setup expects a table")
  opts = vim.deepcopy(opts or {})
  opts = opts or {}
  local window, lazygit = require("git_tools.diff.window"), require("git_tools.lazygit")
  local buffers = require("git_tools.buffer")
  local diff_options = window.resolve(opts.diff or {})
  local terminal_options = lazygit.resolve(opts.lazygit or {})
  local buffer_options = opts.buffer ~= false and buffers.resolve(opts.buffer) or nil
  window.configure(diff_options)
  lazygit.configure(terminal_options)
  if buffer_options then
    buffers.setup(buffer_options)
  else
    buffers.dispose()
  end
  require("git_tools.user_command").create("GitTools", function(command)
    local name = command.fargs[1] or "status"
    local actions = {
      status = M.status,
      changes = M.changes,
      branches = M.branches,
      stash = M.stash,
      log = M.log,
      file_history = M.file_history,
      line_history = M.line_history,
      blame = M.blame,
      browse = M.browse,
      compare = M.compare,
      merge = M.merge,
      lazygit = M.lazygit,
      stage = M.stage_hunk,
      unstage = M.unstage_hunk,
      reset = M.reset_hunk,
      stage_buffer = M.stage_buffer,
      unstage_buffer = M.unstage_buffer,
      reset_buffer = M.reset_buffer,
    }
    if not actions[name] then
      error("Unknown GitTools action: " .. name)
    end
    local args = {}
    if name == "compare" then
      args.from, args.to = command.fargs[2], command.fargs[3]
    end
    if name == "log" then
      args.rev = command.fargs[2]
    end
    if command.range > 0 then
      args.range = { command.line1, command.line2 }
    end
    actions[name](args)
  end, {
    nargs = "*",
    range = true,
    force = true,
    complete = function()
      return {
        "status",
        "changes",
        "branches",
        "stash",
        "log",
        "file_history",
        "line_history",
        "blame",
        "browse",
        "compare",
        "merge",
        "lazygit",
        "stage",
        "unstage",
        "reset",
        "stage_buffer",
        "unstage_buffer",
        "reset_buffer",
      }
    end,
  })
end

function M.dispose()
  for _, name in ipairs({ "buffer", "view", "lazygit" }) do
    local module = package.loaded["git_tools." .. name]
    if module then
      module.dispose()
    end
  end
  local window = package.loaded["git_tools.diff.window"]
  if window then
    window.configure()
  end
  local commands = package.loaded["git_tools.user_command"]
  if commands then
    commands.delete("GitTools")
  end
end

function M.stage_hunk(opts)
  return require("git_tools.actions").change("stage", opts)
end
function M.unstage_hunk(opts)
  return require("git_tools.actions").change("unstage", opts)
end
function M.reset_hunk(opts)
  return require("git_tools.actions").change("reset", opts)
end
function M.stage_buffer(opts)
  return M.stage_hunk(vim.tbl_extend("force", {}, opts or {}, { all = true }))
end
function M.unstage_buffer(opts)
  return M.unstage_hunk(vim.tbl_extend("force", {}, opts or {}, { all = true }))
end
function M.reset_buffer(opts)
  return M.reset_hunk(vim.tbl_extend("force", {}, opts or {}, { all = true }))
end
function M.nav_hunk(direction, opts)
  return require("git_tools.actions").nav(direction, opts)
end
function M.select_hunk()
  return require("git_tools.actions").select()
end
function M.preview_hunk(opts)
  return require("git_tools.actions").preview(opts)
end
function M.toggle_overlay(buf)
  return require("git_tools.buffer").toggle_overlay(buf)
end
function M.toggle(name, value)
  return require("git_tools.buffer").toggle(name, value)
end
function M.get_hunks(buf)
  return require("git_tools.buffer").get_hunks(buf)
end
function M.quickfix(opts)
  return require("git_tools.actions").quickfix(opts)
end

function M.browse(opts, callback)
  return require("git_tools.browse").open(opts, callback)
end

function M.status(opts)
  return require("git_tools.status").open(opts)
end

function M.log(opts)
  return require("git_tools.history").open(opts)
end
function M.changes(opts)
  return require("git_tools.changes").open(opts)
end
function M.branches(opts)
  return require("git_tools.branches").open(opts)
end
function M.stash(opts)
  return require("git_tools.stash").open(opts)
end
function M.file_history(opts)
  return M.log(vim.tbl_extend("force", {}, opts or {}, { file = true }))
end
function M.line_history(opts)
  opts = vim.tbl_extend("force", {}, opts or {})
  opts.range = opts.range or { vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_win_get_cursor(0)[1] }
  return M.log(opts)
end
function M.blame(opts, callback)
  return require("git_tools.history").blame(opts, callback)
end

return M
