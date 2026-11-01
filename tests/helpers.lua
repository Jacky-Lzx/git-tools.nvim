local M = {}
function M.wait(predicate, message)
  assert(vim.wait(5000, predicate, 5), message or "Async operation timed out")
end
function M.result(start)
  local done, failure, value
  start(function(err, result)
    failure, value, done = err, result, true
  end)
  M.wait(function()
    return done
  end)
  return failure, value
end
function M.await(start)
  local err, result = M.result(start)
  assert(not err, err)
  return result
end
function M.fixture()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = vim.uv.fs_realpath(root)
  local f = { root = root }
  function f:result(...)
    local args = { "git", "-C", self.root, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null" }
    vim.list_extend(args, { ... })
    return vim.system(args):wait()
  end
  function f:git(...)
    local r = self:result(...)
    assert(r.code == 0, r.stderr)
    return r.stdout
  end
  function f:write(path, lines)
    vim.fn.writefile(lines, self.root .. "/" .. path)
  end
  function f:bytes(path, text)
    local fd = assert(vim.uv.fs_open(self.root .. "/" .. path, "w", 420))
    assert(vim.uv.fs_write(fd, text))
    assert(vim.uv.fs_close(fd))
  end
  function f:cleanup()
    vim.fn.delete(self.root, "rf")
  end
  f:git("init", "-qb", "main")
  f:git("config", "user.name", "Fixture")
  f:git("config", "user.email", "fixture@example.invalid")
  f:git("config", "core.autocrlf", "false")
  return f
end
return M
