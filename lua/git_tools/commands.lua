local registry = require("base_tools.user_command").new()
local M = {}
local default_compare_revision = "HEAD~1"

local function command_options(command)
  return command.range > 0 and { range = { command.line1, command.line2 } } or {}
end

local function revision_candidates()
  return vim.list_extend({ "HEAD", default_compare_revision }, require("git_tools.revisions").list())
end

function M.setup(git)
  local function action(name, method)
    return {
      name = name,
      run = function(command)
        return git[method or name](command_options(command))
      end,
    }
  end

  registry.create_group("GitTools", {
    default = "status",
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
    },
  }, { range = true })
end

function M.dispose()
  registry.delete("GitTools")
end

return M
