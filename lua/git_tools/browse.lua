local git = require("git_tools.git")
local M = {}

local function encode(text, slash)
  return (
    text:gsub("([^%w%-_%.~" .. (slash and "/" or "") .. "])", function(char)
      return string.format("%%%02X", char:byte())
    end)
  )
end

function M.remote(url)
  local host, path = url:match("^%w[%w+.-]*://([^/]+)/(.+)$")
  if not host then
    host, path = url:match("^[^@]+@([^:]+):(.+)$")
  end
  if not host then
    return nil, "Unsupported remote URL"
  end
  host = host:gsub("^.*@", ""):gsub(":%d+$", "")
  path = path:gsub("/+$", ""):gsub("%.git$", "")
  if path == "" or host == "" then
    return nil, "Invalid remote URL"
  end
  return { host = host, path = path }
end

function M.url(remote, revision, path, opts)
  opts = opts or {}
  local provider = opts.provider
    or ({
      ["github.com"] = "github",
      ["gitlab.com"] = "gitlab",
      ["bitbucket.org"] = "bitbucket",
      ["codeberg.org"] = "gitea",
    })[remote.host]
  if opts.url then
    return opts.url(remote, revision, path, opts)
  end
  if not provider then
    return nil, "Unknown Git host; set provider or a custom url function"
  end
  local base = (opts.base_url or ("https://" .. remote.host .. "/" .. encode(remote.path, true))):gsub("/$", "")
  local commit_routes = { github = "/commit/", gitlab = "/-/commit/", bitbucket = "/commits/", gitea = "/commit/" }
  local file_routes = { github = "/blob/", gitlab = "/-/blob/", bitbucket = "/src/", gitea = "/src/commit/" }
  if not file_routes[provider] then
    return nil, "Unsupported provider: " .. tostring(provider)
  end
  if opts.commit then
    return base .. commit_routes[provider] .. encode(revision)
  end
  local route = file_routes[provider]
  if provider == "gitea" and opts.permalink == false then
    route = "/src/branch/"
  end
  local url = base .. route .. encode(revision) .. "/" .. encode(path, true)
  local range = opts.range
  if range then
    local a, b = math.min(range[1], range[2]), math.max(range[1], range[2])
    if provider == "bitbucket" then
      url = url .. "#lines-" .. a .. (a ~= b and (":" .. b) or "")
    elseif provider == "gitlab" then
      url = url .. "#L" .. a .. (a ~= b and ("-" .. b) or "")
    else
      url = url .. "#L" .. a .. (a ~= b and ("-L" .. b) or "")
    end
  end
  return url
end

function M.open(opts, callback)
  opts = vim.tbl_extend("force", {}, opts or {})
  local path = opts.path or vim.api.nvim_buf_get_name(0)
  local task = git.task()
  local function finish(err, url)
    if callback then
      callback(err, url)
      return
    end
    if err then
      git.notify(err)
      return
    end
    if opts.copy then
      vim.fn.setreg("+", url)
      vim.notify("Copied " .. url, vim.log.levels.INFO, { title = "Git tools" })
    else
      local opened, result, failure = pcall(opts.open or vim.ui.open, url)
      if not opened then
        git.notify(result)
      elseif not result and failure then
        git.notify(failure)
      end
    end
  end
  git.discover(task, opts, function(err, repo)
    if err then
      finish(err)
      return
    end
    local relative, path_err
    if not opts.commit then
      relative, path_err = git.path(repo, path)
    end
    if path_err then
      finish(path_err)
      return
    end
    local function with_revision(revision)
      local function remote_url(name)
        git.run(task, repo.root, { "remote", "get-url", "--", name }, function(remote_err, output)
          if remote_err then
            finish(remote_err)
            return
          end
          local remote, parse_err = M.remote(output:gsub("\n$", ""))
          if parse_err then
            finish(parse_err)
            return
          end
          local url, url_err = M.url(remote, revision, relative, opts)
          finish(url_err, url)
        end)
      end
      if opts.remote then
        remote_url(opts.remote)
        return
      end
      git.run(task, repo.root, { "config", "--get", "branch." .. (opts.branch or "") .. ".remote" }, function(_, remote)
        remote = remote:gsub("\n$", "")
        remote_url(remote ~= "" and remote ~= "." and remote or "origin")
      end)
    end
    local function resolve()
      require("git_tools.history").resolve(
        task,
        repo,
        type(opts.commit) == "string" and opts.commit or "HEAD",
        function(rev_err, sha)
          if rev_err then
            finish(rev_err)
          else
            with_revision(sha)
          end
        end
      )
    end
    local function tracked()
      if opts.commit then
        resolve()
        return
      end
      git.run(task, repo.root, { "ls-files", "--error-unmatch", "--", relative }, function(track_err)
        if track_err then
          finish("File is not tracked by Git: " .. relative)
          return
        end
        if opts.permalink == false then
          git.run(task, repo.root, { "symbolic-ref", "--quiet", "--short", "HEAD" }, function(branch_err, branch)
            if branch_err then
              resolve()
            else
              opts.branch = branch:gsub("\n$", "")
              with_revision(opts.branch)
            end
          end)
        else
          resolve()
        end
      end)
    end
    -- Use the current branch's upstream remote even for fixed-commit links.
    git.run(task, repo.root, { "symbolic-ref", "--quiet", "--short", "HEAD" }, function(_, branch)
      opts.branch = branch:gsub("\n$", "")
      tracked()
    end)
  end)
  return task
end

return M
