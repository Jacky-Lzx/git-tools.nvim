local git = require("git_tools.git")
local M = {}
local directories, repositories = {}, {}
local ttl, timeout = 2000, 75
local ref_args = {
  "-c",
  "core.warnAmbiguousRefs=true",
  "for-each-ref",
  "--sort=refname",
  "--format=%(refname:short)%09%(symref)",
  "refs/heads",
  "refs/remotes",
  "refs/tags",
}

local function parse(output)
  local refs = {}
  for line in (output or ""):gmatch("[^\r\n]+") do
    -- A nonempty symref is an alias such as origin/HEAD.
    local name = line:match("^([^\t]+)\t$")
    if name then
      refs[#refs + 1] = name
    end
  end
  return refs
end

local function refresh(root, cached)
  cached.task = git.task()
  git.run(cached.task, root, ref_args, function(err, output)
    cached.task = nil
    cached.expires = vim.uv.hrtime() / 1e6 + ttl
    if not err then
      cached.refs = parse(output)
    end
  end)
end

function M.list()
  local directory = git.directory()
  local now = vim.uv.hrtime() / 1e6
  local context = directories[directory]
  if not context or now >= context.expires then
    local root = git.read(directory, { "rev-parse", "--show-toplevel" }, timeout)
    context = { root = root and root:gsub("\n$", ""), expires = now + ttl }
    directories[directory] = context
  end
  if not context.root then
    return {}
  end

  local cached = repositories[context.root]
  if not cached then
    local output, code = git.read(context.root, ref_args, timeout)
    cached = { refs = parse(output), expires = now + ttl }
    repositories[context.root] = cached
    if code == 124 then
      refresh(context.root, cached)
    end
  elseif not cached.task and now >= cached.expires then
    refresh(context.root, cached)
  end
  return cached.refs
end

function M.dispose()
  for _, cached in pairs(repositories) do
    if cached.task then
      cached.task:close()
    end
  end
  directories, repositories = {}, {}
end

return M
