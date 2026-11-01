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
  local base = (opts.base_url or ("https://" .. remote.host .. "/" .. encode(remote.path, true))):gsub("/$", "")
  if opts.what == "repo" then
    return base
  end
  if not provider then
    return nil, "Unknown Git host; set provider or a custom url function"
  end
  local commit_routes = { github = "/commit/", gitlab = "/-/commit/", bitbucket = "/commits/", gitea = "/commit/" }
  local file_routes = { github = "/blob/", gitlab = "/-/blob/", bitbucket = "/src/", gitea = "/src/commit/" }
  if not file_routes[provider] then
    return nil, "Unsupported provider: " .. tostring(provider)
  end
  if opts.what == "commit" or (not opts.what and opts.commit) then
    return base .. commit_routes[provider] .. encode(revision)
  end
  if opts.what == "branch" then
    local routes = { github = "/tree/", gitlab = "/-/tree/", bitbucket = "/src/", gitea = "/src/branch/" }
    return base .. routes[provider] .. encode(revision)
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
  local word = opts.word
  if not word then
    local ok, value = pcall(vim.fn.expand, "<cword>")
    word = ok and value or ""
  end
  local has_file = opts.path ~= nil or (vim.bo.buftype == "" and path ~= "")
  local task = git.task()
  local function finish(err, url)
    if task.cancelled then
      return
    end
    if callback then
      callback(err, url)
      return
    end
    if err then
      git.notify(err)
      return
    end
    if not url then
      return
    end
    if opts.copy then
      vim.fn.setreg("+", url)
      vim.notify("Copied " .. url, vim.log.levels.INFO, { title = "Git tools" })
    else
      local ok, result, failure = pcall(opts.open or vim.ui.open, url)
      if not ok then
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
    local what = opts.what or (opts.commit and "commit") or "auto"
    if not vim.tbl_contains({ "auto", "repo", "branch", "file", "commit", "permalink" }, what) then
      finish("Unknown browse target: " .. tostring(what))
      return
    end
    local current_branch
    local function publish(revision, relative)
      local function remote_url(name)
        if task.cancelled then
          return
        end
        if not name then
          finish()
          return
        end
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
      git.run(task, repo.root, { "remote" }, function(list_err, output)
        if list_err then
          finish(list_err)
          return
        end
        local names = git.lines(output)
        if #names == 0 then
          finish("Repository has no remotes")
          return
        end
        git.run(
          task,
          repo.root,
          { "config", "--get", "branch." .. (current_branch or "") .. ".remote" },
          function(_, upstream)
            upstream = upstream:gsub("\n$", "")
            local preferred = vim.tbl_contains(names, upstream) and upstream
              or vim.tbl_contains(names, "origin") and "origin"
              or names[1]
            table.sort(names, function(a, b)
              if a == preferred then
                return b ~= preferred
              end
              if b == preferred then
                return false
              end
              return a < b
            end)
            if #names == 1 or opts.select_remote == false then
              remote_url(preferred)
            elseif type(opts.select_remote) == "function" then
              opts.select_remote(names, remote_url)
            else
              vim.ui.select(names, { prompt = "Git remote" }, remote_url)
            end
          end
        )
      end)
    end
    local function resolve(revision, done)
      require("git_tools.history").resolve(task, repo, revision, done)
    end
    local function target()
      opts.what = what
      if what == "repo" then
        publish(nil)
        return
      end
      if what == "branch" then
        local branch = opts.branch or current_branch
        if not branch or branch == "" then
          finish("Detached HEAD: specify branch for a branch URL")
          return
        end
        resolve(branch, function(branch_err)
          if branch_err then
            finish(branch_err)
          else
            publish(branch)
          end
        end)
        return
      end
      if what == "commit" then
        resolve(type(opts.commit) == "string" and opts.commit or "HEAD", function(rev_err, sha)
          if rev_err then
            finish(rev_err)
          else
            publish(sha)
          end
        end)
        return
      end
      local relative, path_err = git.path(repo, path)
      if path_err then
        finish(path_err)
        return
      end
      git.run(task, repo.root, { "ls-files", "--error-unmatch", "--", relative }, function(track_err)
        if track_err then
          finish("File is not tracked by Git: " .. relative)
          return
        end
        if what == "permalink" then
          opts.permalink = true
        end
        if opts.permalink == false and (opts.branch or current_branch) then
          publish(opts.branch or current_branch, relative)
        else
          resolve("HEAD", function(rev_err, sha)
            if rev_err then
              finish(rev_err)
            else
              publish(sha, relative)
            end
          end)
        end
      end)
    end
    git.run(task, repo.root, { "symbolic-ref", "--quiet", "--short", "HEAD" }, function(_, branch)
      current_branch = branch:gsub("\n$", "")
      if current_branch == "" then
        current_branch = nil
      end
      if what ~= "auto" then
        target()
        return
      end
      local function fallback()
        what = has_file and "file" or "repo"
        target()
      end
      if not opts.range and word:match("^%x+$") and #word >= 7 and #word <= 64 then
        resolve(word, function(hash_err, sha)
          if hash_err then
            fallback()
          else
            what = "commit"
            opts.commit = sha
            target()
          end
        end)
      else
        fallback()
      end
    end)
  end)
  return task
end

return M
