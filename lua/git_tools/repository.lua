local git = require("git_tools.git")
local M = {}

-- Porcelain -z does not quote paths; rename records contain destination, source.
function M.parse_status(output, root)
  local fields = vim.split(output, "\0", { plain = true })
  local entries, i = {}, 1
  while i < #fields do
    local record = fields[i]
    local xy, path = record:sub(1, 2), record:sub(4)
    local original
    if xy:find("[RC]") then
      i = i + 1
      original = fields[i]
    end
    local function add(kind, status)
      entries[#entries + 1] = {
        kind = kind,
        status = status,
        path = path,
        old_path = original,
        file = root .. "/" .. path,
        root = root,
        lnum = 1,
        text = string.format("%-9s %s %s", kind, status, path),
      }
    end
    if xy == "??" then
      add("untracked", "?")
    elseif xy == "!!" then -- ignored entries are deliberately omitted
    elseif xy:find("U") or xy == "AA" or xy == "DD" then
      add("conflict", xy)
    else
      if xy:sub(1, 1) ~= " " then
        add("staged", xy:sub(1, 1))
      end
      if xy:sub(2, 2) ~= " " then
        add("unstaged", xy:sub(2, 2))
      end
    end
    i = i + 1
  end
  return entries
end

function M.status(task, repo, callback)
  git.run(task, repo.root, { "status", "--porcelain=v1", "-z", "--untracked-files=all" }, function(err, output)
    callback(err, not err and M.parse_status(output, repo.root) or nil)
  end)
end

function M.patch(task, item, callback, opts)
  opts = opts or {}
  if item.kind == "untracked" then
    -- Git produces binary summaries and exact newline/CRLF patches as well.
    git.run(task, item.root, {
      "diff",
      "--no-index",
      "--no-ext-diff",
      "--no-textconv",
      "--no-color",
      "--",
      "/dev/null",
      item.path,
    }, function(err, output, code)
      local failure
      if code ~= 0 and code ~= 1 then
        failure = err
      end
      callback(failure, git.lines(output))
    end)
    return
  end
  local args = { "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=3" }
  if item.kind == "staged" then
    args[#args + 1] = "--cached"
  end
  if opts.revisions then
    vim.list_extend(args, opts.revisions)
  end
  args[#args + 1] = "--"
  args[#args + 1] = item.path
  if item.old_path then
    args[#args + 1] = item.old_path
  end
  git.run(task, item.root, args, function(err, output)
    local lines = git.lines(output)
    for _, line in ipairs(lines) do
      local lnum = line:match("^@@ .- %+(%d+)")
      if lnum then
        item.lnum = math.max(1, tonumber(lnum))
        item.pos = { item.lnum, 0 }
        break
      end
    end
    callback(err, lines)
  end)
end

return M
