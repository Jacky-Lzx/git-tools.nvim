local git = require("git_tools.git")
local ui = require("git_tools.ui")
local M = {}

function M.resolve(task, repo, revision, callback)
  git.run(
    task,
    repo.root,
    { "rev-parse", "--verify", "--end-of-options", revision .. "^{commit}" },
    function(err, output)
      callback(err, not err and output:gsub("\n$", "") or nil)
    end
  )
end

function M.query(task, repo, opts, callback)
  opts = opts or {}
  local limit = opts.limit or 200
  assert(type(limit) == "number" and limit >= 1 and limit % 1 == 0, "History limit must be a positive integer")
  local args = { "log", "--no-color", "--no-patch", "-z", "--format=%H%x00%an%x00%aI%x00%s", "-n", tostring(limit) }
  local path, path_err
  if opts.file or opts.range then
    path, path_err = git.path(repo, opts.path)
  end
  if path_err then
    callback(path_err)
    return
  end
  if opts.range then
    local a, b = opts.range[1], opts.range[2]
    assert(a >= 1 and b >= a and a % 1 == 0 and b % 1 == 0, "Invalid history line range")
    args[#args + 1] = "-L" .. a .. "," .. b .. ":" .. path
  elseif path then
    args[#args + 1] = "--follow"
  end
  local function load(revision)
    if revision then
      args[#args + 1] = revision
    end
    if not opts.range then
      args[#args + 1] = "--"
      if path then
        args[#args + 1] = path
      end
    end
    git.run(task, repo.root, args, function(err, output)
      if err then
        callback(err)
        return
      end
      local fields, items = vim.split(output, "\0", { plain = true }), {}
      for i = 1, #fields - 3, 4 do
        local sha, author, date, subject = fields[i], fields[i + 1], fields[i + 2], fields[i + 3]
        items[#items + 1] = {
          sha = sha,
          author = author,
          date = date,
          subject = subject,
          root = repo.root,
          path = path,
          range = opts.range,
          text = string.format("%s %s %s  %s", sha:sub(1, 10), date:sub(1, 10), author, subject),
        }
      end
      callback(nil, items)
    end)
  end
  if opts.rev then
    M.resolve(task, repo, opts.rev, function(err, sha)
      if err then
        callback(err)
      else
        load(sha)
      end
    end)
  else
    load()
  end
end

function M.patch(task, item, callback)
  local args =
    { "show", "--format=fuller", "--no-ext-diff", "--no-textconv", "--no-color", "--full-index", item.sha, "--" }
  -- A followed file can have a different historical name. Preview the complete
  -- commit rather than filtering it with the current filename and hiding data.
  git.run(task, item.root, args, function(err, output)
    callback(err, git.lines(output))
  end)
end

function M.show(item)
  local task = git.task()
  M.patch(task, item, function(err, lines)
    if err then
      git.notify(err)
      return
    end
    ui.scratch(lines, item.sha:sub(1, 12))
  end)
  return task
end

function M.open(opts)
  opts = vim.tbl_extend("force", {}, opts or {})
  -- Capture the source file before a picker or a split becomes current.
  if opts.file or opts.range then
    opts.path = opts.path or vim.api.nvim_buf_get_name(0)
  end
  return ui.pick(
    opts,
    opts.range and "Git line history" or opts.file and "Git file history" or "Git log",
    function(task, repo, callback)
      M.query(task, repo, opts, callback)
    end,
    ui.preview(M.patch, opts),
    M.show,
    {
      actions = {
        compare_commit = function(picker)
          local item = picker:current()
          if item then
            picker:close()
            require("git_tools").compare({ cwd = item.root, commit = item.sha })
          end
        end,
      },
      keys = { compare_commit = { "<C-d>" } },
    }
  )
end

function M.blame(opts, callback)
  opts = vim.tbl_extend("force", {}, opts or {})
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local path = opts.path or vim.api.nvim_buf_get_name(buf)
  local range = opts.range or { vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_win_get_cursor(0)[1] }
  local contents
  if not opts.path then
    contents = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      .. (vim.bo[buf].endofline and "\n" or "")
  end
  local task = git.task()
  git.discover(task, vim.tbl_extend("force", opts, { buf = buf }), function(err, repo)
    if err then
      (callback or git.notify)(err)
      return
    end
    local relative, path_err = git.path(repo, path)
    if path_err then
      (callback or git.notify)(path_err)
      return
    end
    local args = { "blame", "--line-porcelain", "-L", range[1] .. "," .. range[2] }
    if contents then
      vim.list_extend(args, { "--contents", "-" })
    end
    vim.list_extend(args, { "--", relative })
    git.run(task, repo.root, args, function(blame_err, output)
      if blame_err then
        (callback or git.notify)(blame_err)
        return
      end
      local items, item = {}, nil
      for _, line in ipairs(git.lines(output)) do
        local sha, original, final = line:match("^(%x+) (%d+) (%d+)")
        if sha then
          item = { sha = sha, original = tonumber(original), lnum = tonumber(final), root = repo.root, path = relative }
          items[#items + 1] = item
        elseif item then
          local key, value = line:match("^(%S+) (.*)")
          if line:sub(1, 1) == "\t" then
            item.code = line:sub(2)
          elseif key then
            item[key] = value
          end
        end
      end
      for _, entry in ipairs(items) do
        entry.uncommitted = entry.sha:match("^0+$") ~= nil
        entry.text =
          string.format("%d %s %s  %s", entry.lnum, entry.sha:sub(1, 10), entry.author or "", entry.summary or "")
      end
      if callback then
        callback(nil, items)
        return
      end
      local ok, selection = pcall(require, "selection_tools")
      if not ok then
        git.notify("Install selection-tools.nvim to inspect blame")
        return
      end
      selection.open({
        prompt = "Git blame",
        items = items,
        resume = false,
        format_item = function(entry)
          return entry.text
        end,
        preview = {
          enabled = true,
          providers = {
            ui.preview(function(t, entry, cb)
              if entry.uncommitted then
                cb(nil, { "Uncommitted buffer change", entry.code or "" })
              else
                M.patch(t, entry, cb)
              end
            end, opts),
          },
        },
        on_choice = function(entry)
          if entry and not entry.uncommitted then
            M.show(entry)
          end
        end,
      })
    end, { stdin = contents })
  end)
  return task
end

return M
