-- Git I/O is separate from the dependency-free text diff core.
local M = {}
local env = { GIT_TERMINAL_PROMPT = "0", GIT_LITERAL_PATHSPECS = "1", GIT_OPTIONAL_LOCKS = "0", LC_ALL = "C" }

local function command(args)
  return vim.list_extend({ "git", "--no-pager", "-c", "core.quotepath=false" }, args)
end

function M.task()
  return require("base_tools.process").new()
end

function M.run(task, cwd, args, callback, opts)
  opts = opts or {}

  task:run(command(args), {
    cwd = cwd,
    stdin = opts.stdin,
    timeout = opts.timeout or 10000,
    env = env,
  }, function(output, launch_error)
    if launch_error then
      callback(launch_error, "", -1)
      return
    end

    local err = output.code ~= 0 and ((output.stderr or ""):gsub("%s+$", "")) or nil
    if err == "" then
      err = "git exited with code " .. output.code
    end

    callback(err, output.stdout or "", output.code)
  end)
end

-- Native command completion is synchronous. Limit waits and let callers use a fallback.
function M.read(cwd, args, timeout)
  local ok, process = pcall(vim.system, command(args), { cwd = cwd, env = env })
  if ok then
    local result = process:wait(timeout)
    if result.code == 0 then
      return result.stdout or ""
    end
    return nil, result.code
  end
end

function M.directory(opts)
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
  return path
end

function M.discover(task, opts, callback)
  M.run(task, M.directory(opts), { "rev-parse", "--show-toplevel" }, function(err, root)
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
