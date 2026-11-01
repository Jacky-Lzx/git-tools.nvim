-- Git I/O is separate from the dependency-free text diff core.
local M = {}

function M.task()
  local task = { cancelled = false, processes = {} }
  function task:close()
    self.cancelled = true
    for process in pairs(self.processes) do
      if not process:is_closing() then
        process:kill(15)
      end
    end
    self.processes = {}
  end
  return task
end

function M.run(task, cwd, args, callback, opts)
  if task.cancelled then
    return
  end
  opts = opts or {}
  local argv = { "git", "--no-pager", "-c", "core.quotepath=false" }
  vim.list_extend(argv, args)
  local process
  local ok, result = pcall(vim.system, argv, {
    cwd = cwd,
    stdin = opts.stdin,
    timeout = opts.timeout or 10000,
    env = { GIT_TERMINAL_PROMPT = "0", GIT_LITERAL_PATHSPECS = "1", GIT_OPTIONAL_LOCKS = "0", LC_ALL = "C" },
  }, function(output)
    vim.schedule(function()
      if process then
        task.processes[process] = nil
      end
      if task.cancelled then
        return
      end
      local err = output.code ~= 0 and ((output.stderr or ""):gsub("%s+$", "")) or nil
      if err == "" then
        err = "git exited with code " .. output.code
      end
      callback(err, output.stdout or "", output.code)
    end)
  end)
  if ok then
    process = result
    task.processes[process] = true
  else
    vim.schedule(function()
      if not task.cancelled then
        callback(tostring(result), "", -1)
      end
    end)
  end
end

function M.discover(task, opts, callback)
  opts = opts or {}
  local path = opts.cwd
  if not path then
    path = vim.api.nvim_buf_get_name(opts.buf or 0)
    if path == "" or vim.bo[opts.buf or 0].buftype ~= "" then
      path = vim.fn.getcwd()
    end
  end
  path = vim.fn.fnamemodify(path, ":p")
  if vim.fn.isdirectory(path) ~= 1 then
    path = vim.fs.dirname(path)
  end
  M.run(task, path, { "rev-parse", "--show-toplevel" }, function(err, root)
    if err then
      callback(err)
      return
    end
    root = root:gsub("\n$", "")
    M.run(task, root, { "rev-parse", "--absolute-git-dir" }, function(dir_err, dir)
      callback(dir_err, not dir_err and { root = root, git_dir = dir:gsub("\n$", "") } or nil)
    end)
  end)
end

function M.path(repo, path)
  local absolute = vim.fn.fnamemodify(path or vim.api.nvim_buf_get_name(0), ":p")
  local parent = vim.uv.fs_realpath(vim.fs.dirname(absolute))
  if parent then
    absolute = parent .. "/" .. vim.fs.basename(absolute)
  end
  local prefix = repo.root .. "/"
  if absolute:sub(1, #prefix) ~= prefix then
    return nil, "File is outside the repository"
  end
  return absolute:sub(#prefix + 1)
end

function M.lines(text)
  if text == "" then
    return {}
  end
  return vim.split(text:gsub("\n$", ""), "\n", { plain = true })
end

function M.notify(err)
  if err then
    vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Git tools" })
  end
end

return M
