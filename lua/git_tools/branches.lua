local git, ui, history = require("git_tools.git"), require("git_tools.ui"), require("git_tools.history")
local operations = require("git_tools.operations")
local M = {}

function M.query(task, repo, opts, callback)
  local args = {
    "for-each-ref",
    "--sort=refname",
    "--format=%(refname)%00%(objectname)%00%(HEAD)%00%(upstream)%00%(worktreepath)%00%(symref)%00",
    "refs/heads",
  }
  if opts.all then
    args[#args + 1] = "refs/remotes"
  end
  git.run(task, repo.root, args, function(err, output)
    if err then
      callback(err)
      return
    end
    local fields, items = vim.split(output, "\0", { plain = true }), {}
    for i = 1, #fields - 5, 6 do
      local ref = fields[i]:gsub("^\n", "")
      if fields[i + 5] == "" then
        local remote = ref:sub(1, 13) == "refs/remotes/"
        local name = ref:gsub("^refs/heads/", ""):gsub("^refs/remotes/", "")
        local current = fields[i + 2] == "*"
        items[#items + 1] = {
          root = repo.root,
          git_dir = repo.git_dir,
          ref = ref,
          sha = fields[i + 1],
          current = current,
          upstream = fields[i + 3],
          worktree = fields[i + 4],
          remote = remote,
          name = name,
          text = string.format(
            "%s %-6s %s %s",
            current and "*" or " ",
            remote and "remote" or "local",
            name,
            fields[i + 1]:sub(1, 10)
          ),
        }
      end
    end
    callback(nil, items)
  end)
end

local function fresh(task, item, callback)
  history.resolve(task, { root = item.root }, item.ref, function(err, sha)
    callback(err or (sha ~= item.sha and "Branch changed; refresh and retry" or nil))
  end)
end

function M.switch(item, opts, callback)
  callback = callback or git.notify
  if not item then
    callback(nil, false)
    return
  end
  local err = operations.unsaved({ root = item.root })
  if err then
    callback(err)
    return
  end
  local task = git.task()
  fresh(task, item, function(stale)
    if stale then
      callback(stale)
      return
    end
    local unsaved = operations.unsaved({ root = item.root })
    if unsaved then
      callback(unsaved)
      return
    end
    local args
    if item.remote then
      local name = item.name:match("^[^/]+/(.+)$")
      if not name then
        callback("Invalid remote branch")
        return
      end
      args = { "switch", "--track", "-c", name, "--", item.ref }
    else
      args = { "switch", "--", item.name }
    end
    git.run(task, item.root, args, function(switch_err)
      if not switch_err then
        operations.refresh()
      end
      callback(switch_err, not switch_err)
    end)
  end)
  return task
end

function M.create(repo, name, opts, callback)
  opts, callback = opts or {}, callback or git.notify
  if not name or name == "" then
    callback(nil, false)
    return
  end
  if name:sub(1, 1) == "-" or name:find("@{", 1, true) then
    callback("Invalid branch name")
    return
  end
  local task = git.task()
  git.run(task, repo.root, { "check-ref-format", "--branch", name }, function(err)
    if err then
      callback(err)
      return
    end
    history.resolve(task, repo, opts.start or "HEAD", function(rev_err, sha)
      if rev_err then
        callback(rev_err)
        return
      end
      git.run(task, repo.root, { "branch", "--", name, sha }, function(create_err)
        callback(create_err, not create_err)
      end)
    end)
  end)
  return task
end

function M.delete(item, opts, callback)
  callback = callback or git.notify
  if not item then
    callback(nil, false)
    return
  end
  if item.remote then
    callback("Delete supports local branches only")
    return
  end
  if item.current or item.worktree ~= "" then
    callback("Branch is checked out in a worktree")
    return
  end
  if not operations.confirm("Delete merged local branch " .. item.name .. "?", opts) then
    callback(nil, false)
    return
  end
  local task = git.task()
  fresh(task, item, function(stale)
    if stale then
      callback(stale)
      return
    end
    git.run(task, item.root, { "branch", "-d", "--", item.name }, function(err)
      callback(err, not err)
    end)
  end)
  return task
end

function M.open(opts)
  opts = opts or {}
  local repo
  local function load(task, current, callback)
    repo = current
    M.query(task, repo, opts, callback)
  end
  local controller = operations.controller(function(task, cb)
    load(task, repo, cb)
  end)
  local function switch(item)
    M.switch(item, opts)
  end
  return ui.pick(
    opts,
    "Git branches · Enter switches",
    load,
    ui.preview(function(task, item, cb)
      git.run(
        task,
        item.root,
        { "log", "--no-color", "-n", "30", "--format=%h %ad %s", "--date=short", item.sha, "--" },
        function(err, output)
          cb(err, git.lines(output))
        end
      )
    end, opts),
    switch,
    {
      components = require("git_tools.picker_components").for_kind("branches"),
      actions = {
        refresh = function(p)
          if repo then
            controller:refresh(p)
          end
        end,
        create = function(p)
          if not repo then
            return
          end
          controller:run(p, function(done)
            local function submit(name)
              if p.closed then
                done(nil, false)
              else
                M.create(repo, name, opts, done)
              end
            end
            if opts.input then
              opts.input(submit)
            else
              vim.ui.input({ prompt = "New branch: " }, submit)
            end
          end)
        end,
        delete = function(p)
          local item = p:current()
          controller:run(p, function(done)
            M.delete(item, opts, done)
          end)
        end,
      },
      keys = { refresh = { "<F5>" }, create = { "<C-a>" }, delete = { "<C-d>" }, preview_down = {} },
      on_close = function()
        controller:close()
      end,
    }
  )
end
return M
