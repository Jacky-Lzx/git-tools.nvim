local user_command = require("base_tools.user_command")
local config = require("git_tools.config")
local M = {}
local registry
local default_compare_revision = "HEAD~1"

local function command_options(command)
  return command.range > 0 and { range = { command.line1, command.line2 } } or {}
end

local function revision_candidates()
  return vim.list_extend({ "HEAD", default_compare_revision }, require("git_tools.revisions").list())
end

local function config_value(git, path)
  if not path or path == "" then
    return git.get_config()
  end
  return git.get_config(unpack(vim.split(path, ".", { plain = true })))
end

local function config_candidates(git, lead)
  local prefix = lead:match("^(.*%.)") or ""
  local section = config_value(git, prefix:sub(1, -2))
  local paths = {}
  if type(section) == "table" then
    for key in pairs(section) do
      if type(key) == "string" and not key:find(".", 1, true) then
        paths[#paths + 1] = prefix .. key
      end
    end
    table.sort(paths)
  end
  return paths
end

function M.resolve(git, opts)
  assert(opts == nil or type(opts) == "table", "command must be a table")
  local default = opts and opts.default
  assert(default == nil or type(default) == "string", "command.default must be an action name")

  local function action(name, method)
    return {
      name = name,
      run = function(command)
        return git[method or name](command_options(command))
      end,
    }
  end

  return user_command.group("GitTools", {
    default = default or config.defaults("command", "default"),
    menu = {
      items = function()
        return {
          { id = "status", label = "Changed files", run = git.status },
          { id = "changes", label = "Change hunks", run = git.changes },
          { id = "compare", label = "Compare working tree", run = git.compare },
          {
            id = "last_commit",
            label = "Compare last commit",
            run = function()
              return git.compare({ commit = "HEAD" })
            end,
          },
          { id = "log", label = "Commit history", run = git.log },
          { id = "branches", label = "Branches", run = git.branches },
          { id = "stash", label = "Stash", run = git.stash },
          { id = "lazygit", label = "LazyGit", run = git.lazygit },
        }
      end,
    },
    actions = {
      action("status"),
      action("changes"),
      action("branches"),
      action("stash"),
      {
        name = "log",
        run = function(command)
          local args = command_options(command)
          args.rev = command.fargs[2]
          return git.log(args)
        end,
        complete = { revision_candidates },
      },
      action("file_history"),
      action("line_history"),
      action("blame"),
      action("browse"),
      {
        name = "compare",
        run = function(command)
          local args = command_options(command)
          args.from, args.to = command.fargs[2] or default_compare_revision, command.fargs[3]
          return git.compare(args)
        end,
        complete = { revision_candidates, revision_candidates },
      },
      action("merge"),
      action("lazygit"),
      action("stage", "stage_hunk"),
      action("unstage", "unstage_hunk"),
      action("reset", "reset_hunk"),
      action("stage_buffer"),
      action("unstage_buffer"),
      action("reset_buffer"),
      {
        name = "config",
        run = function(command)
          assert(#command.fargs <= 2, "Usage: GitTools config [option.path]")
          vim.api.nvim_echo({ { vim.inspect(config_value(git, command.fargs[2])) } }, true, {})
        end,
        complete = {
          function(ctx)
            return config_candidates(git, ctx.lead)
          end,
        },
      },
    },
  }, { range = true })
end

function M.setup(definition)
  registry = registry or user_command.new()
  registry.create(unpack(definition))
end

function M.dispose()
  if registry then
    registry.delete("GitTools")
  end
end

return M
