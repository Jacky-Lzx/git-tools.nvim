local git, ui, operations = require("git_tools.git"), require("git_tools.ui"), require("git_tools.operations")
local M = {}
function M.query(task, repo, callback)
  git.run(task, repo.root, { "stash", "list", "-z", "--format=%gd%x00%H%x00%gs" }, function(err, output)
    if err then
      callback(err)
      return
    end
    local fields, items = vim.split(output, "\0", { plain = true }), {}
    for i = 1, #fields - 2, 3 do
      items[#items + 1] = {
        root = repo.root,
        git_dir = repo.git_dir,
        ref = fields[i],
        sha = fields[i + 1],
        subject = fields[i + 2],
        text = fields[i] .. " " .. fields[i + 2],
      }
    end
    callback(nil, items)
  end)
end
function M.patch(task, item, callback)
  git.run(task, item.root, {
    "stash",
    "show",
    "--patch",
    "--include-untracked",
    "--no-ext-diff",
    "--no-textconv",
    "--no-color",
    item.sha,
    "--",
  }, function(err, output)
    callback(err, git.lines(output))
  end)
end
function M.apply(item, opts, callback)
  opts, callback = opts or {}, callback or git.notify
  if not item then
    callback(nil, false)
    return
  end
  local repo = { root = item.root, git_dir = item.git_dir }
  local err = operations.unsaved(repo)
  if err then
    callback(err)
    return
  end
  local task = git.task()
  M.query(task, repo, function(list_err, items)
    if list_err then
      callback(list_err)
      return
    end
    local exists = false
    for _, candidate in ipairs(items) do
      if candidate.sha == item.sha then
        exists = true
        break
      end
    end
    if not exists then
      callback("Stash list changed; refresh and retry")
      return
    end
    local unsaved = operations.unsaved(repo)
    if unsaved then
      callback(unsaved)
      return
    end
    local args = { "stash", "apply" }
    if opts.index then
      args[#args + 1] = "--index"
    end
    args[#args + 1] = item.sha
    git.run(task, repo.root, args, function(apply_err)
      -- Conflicts can update disk/index even when Git exits nonzero.
      operations.refresh()
      callback(apply_err, true)
    end)
  end)
  return task
end
function M.open(opts)
  opts = opts or {}
  local repo
  local function load(task, current, cb)
    repo = current
    M.query(task, repo, cb)
  end
  local controller = operations.controller(function(task, cb)
    load(task, repo, cb)
  end)
  return ui.pick(opts, "Git stash · Enter applies (keeps stash)", load, ui.preview(M.patch, opts), function(item)
    M.apply(item, opts)
  end, {
    actions = {
      refresh = function(p)
        if repo then
          controller:refresh(p)
        end
      end,
    },
    keys = { refresh = { "<F5>" } },
    on_close = function()
      controller:close()
    end,
  })
end
return M
