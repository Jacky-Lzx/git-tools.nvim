local git, repository = require("git_tools.git"), require("git_tools.repository")
local M = {}

function M.refresh()
  pcall(vim.cmd, "checktime")
  local buffer = package.loaded["git_tools.buffer"]
  if buffer then
    for buf in pairs(buffer.states) do
      buffer.schedule(buf)
    end
  end
end

function M.confirm(message, opts)
  if opts and opts.confirm then
    return opts.confirm(message) == true
  end
  return vim.fn.confirm(message, "&Proceed\n&Cancel", 2) == 1
end

function M.modified(file)
  local buf = vim.fn.bufnr(file)
  return buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified
end

function M.unsaved(repo)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and vim.bo[buf].modified then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and git.path(repo, name) then
        return "Unsaved buffer: " .. name
      end
    end
  end
end

function M.files(action, items, opts, callback)
  opts = opts or {}
  callback = callback or git.notify
  if #items == 0 then
    callback("No selected files")
    return
  end
  local first, paths, seen = items[1], {}, {}
  local repo = { root = first.root, git_dir = first.git_dir }
  local function validate()
    for _, item in ipairs(items) do
      if item.root ~= repo.root or not item.snapshot or item.snapshot ~= repository.stamp(repo, item) then
        return "Repository or file changed; refresh and retry"
      end
      if item.kind == "conflict" then
        return "Resolve conflicted files in the merge view"
      end
      if action == "unstage" and item.kind ~= "staged" then
        return "Unstage requires staged entries"
      end
      if action == "stage" and item.kind == "staged" then
        return "Stage requires unstaged or untracked entries"
      end
      if action == "restore" then
        if item.kind ~= "unstaged" then
          return "Discard requires tracked unstaged entries; use Unstage for index changes"
        end
        if M.modified(item.file) then
          return "Unsaved buffer: " .. item.path
        end
      end
    end
  end
  local err = validate()
  if err then
    callback(err)
    return
  end
  if action == "restore" then
    if not M.confirm("Discard disk changes in " .. #items .. " selected entries?", opts) then
      callback(nil, false)
      return
    end
    err = validate()
    if err then
      callback(err)
      return
    end
  end
  for _, item in ipairs(items) do
    for _, path in ipairs({ item.path, item.old_path }) do
      if path and not seen[path] then
        paths[#paths + 1] = path
        seen[path] = true
      end
    end
  end
  local task = git.task()
  local function apply(args)
    args[#args + 1] = "--"
    vim.list_extend(args, paths)
    git.run(task, repo.root, args, function(failure)
      if not failure then
        M.refresh()
      end
      callback(failure, not failure)
    end)
  end
  if action == "stage" then
    apply({ "add" })
  elseif action == "restore" then
    apply({ "restore", "--worktree" })
  elseif action == "unstage" then
    git.run(task, repo.root, { "rev-parse", "--verify", "HEAD" }, function(head_err)
      apply(head_err and { "rm", "--cached", "-f", "-r" } or { "restore", "--staged", "--source=HEAD" })
    end)
  else
    callback("Unknown file operation: " .. tostring(action))
  end
  return task
end

-- Selection-tools owns the UI. Reads cancel on close; an explicitly requested
-- mutation finishes independently, then updates only a still-open picker.
function M.controller(loader)
  local controller = { generation = 0 }
  function controller:refresh(picker)
    if picker.closed then
      return
    end
    if self.read then
      self.read:close()
    end
    self.generation = self.generation + 1
    local generation = self.generation
    self.read = git.task()
    loader(self.read, function(err, items)
      if picker.closed or generation ~= self.generation then
        return
      end
      if err then
        git.notify(err)
      else
        picker:set_items(items)
      end
    end)
  end
  function controller:run(picker, start)
    if self.busy or picker.closed then
      return
    end
    self.busy = true
    start(function(err, changed)
      self.busy = false
      if err then
        git.notify(err)
      end
      if changed ~= false then
        self:refresh(picker)
      end
    end)
  end
  function controller:close()
    if self.read then
      self.read:close()
    end
  end
  return controller
end

return M
