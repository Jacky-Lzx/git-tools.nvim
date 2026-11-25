-- Requiring the plugin installs no mappings, commands, UI or Git processes.
local M = { diff = require("git_tools.diff") }
local configured = false

function M.get_config(...)
  return require("git_tools.config").instance():get(...)
end

-- Snapshot only already-loaded providers; never start Git or create a view.
function M.get_state(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local win = opts.win or vim.api.nvim_get_current_win()
  local buffers, views = package.loaded["git_tools.buffer"], package.loaded["git_tools.view"]
  local result = { initialized = configured }
  if buffers then
    for _, name in ipairs({ "signs", "line_blame", "word_diff" }) do
      result[name] = buffers.config[name] == true
    end
    local state = buffers.states[buf]
    if state then
      result.overlay = state.overlay == true
    end
  end
  if configured or views then
    result.compare = false
    if vim.api.nvim_win_is_valid(win) then
      local tab = vim.api.nvim_win_get_tabpage(win)
      for view in pairs(views and views.active or {}) do
        if view.tab == tab then
          result.compare = true
          break
        end
      end
    end
  end
  return result
end

function M.lazygit(opts)
  return require("git_tools.lazygit").open(opts)
end

function M.compare(opts)
  return require("git_tools.view").open(opts)
end

function M.toggle_compare(opts)
  return require("git_tools.view").toggle(opts)
end

function M.close_compares()
  local views = package.loaded["git_tools.view"]
  if not views then
    return true
  end
  return views.close_all()
end

function M.diffthis(revision)
  return M.compare({ path = vim.api.nvim_buf_get_name(0), from = revision, include_unchanged = true })
end

function M.merge(opts)
  return M.compare(vim.tbl_extend("force", {}, opts or {}, { merge = true }))
end

function M.setup(opts)
  assert(opts == nil or type(opts) == "table", "git-tools.nvim: setup expects a table")
  opts = vim.tbl_extend("force", {}, opts or {})
  local config = require("git_tools.config").instance()
  local compare = require("git_tools.compare_config")
  local buffers = require("git_tools.buffer")
  opts.compare = compare.normalize(opts.compare)
  opts.diff = opts.diff or nil
  opts.lazygit = opts.lazygit or nil
  config:configure(opts, function(candidate)
    local panel_keymap = compare.resolve(candidate.compare)
    local commands = require("git_tools.commands")
    local command = commands.resolve(M, candidate.command)

    commands.setup(command)
    compare.configure(panel_keymap)
    if candidate.buffer == false then
      buffers.dispose()
    else
      buffers.apply(candidate.buffer)
    end
  end)
  configured = true
end

function M.dispose()
  configured = false
  for _, name in ipairs({ "buffer", "view", "lazygit", "revisions" }) do
    local module = package.loaded["git_tools." .. name]
    if module then
      module.dispose()
    end
  end
  local compare = package.loaded["git_tools.compare_config"]
  if compare then
    compare.configure()
  end
  local commands = package.loaded["git_tools.commands"]
  if commands then
    commands.dispose()
  end
  local config = package.loaded["git_tools.config"]
  if config then
    config.reset()
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
  local store = configured and require("git_tools.config").instance() or nil
  return require("git_tools.buffer").toggle(name, value, store)
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
