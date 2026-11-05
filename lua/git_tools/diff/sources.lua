-- Git-specific snapshot acquisition. Reconstruction uses the exact old blob
-- and this patch, including unsaved-on-disk/history/index differences. No read
-- of the present working tree can accidentally color a historical preview.
local M = {}
local git = require("git_tools.git")

local function project(before, hunks)
  local after, cursor = {}, 1
  for _, pair in ipairs(hunks) do
    local old, new = pair[1], pair[2]
    if #old.lines ~= old.count or #new.lines ~= new.count then
      return
    end
    if old.start < cursor or old.start > #before + 1 then
      return
    end
    for i, line in ipairs(old.lines) do
      if before[old.start + i - 1] ~= line then
        return
      end
    end
    for i = cursor, old.start - 1 do
      after[#after + 1] = before[i]
    end
    if new.start ~= #after + 1 then
      return
    end
    vim.list_extend(after, new.lines)
    cursor = old.start + #old.lines
  end
  for i = cursor, #before do
    after[#after + 1] = before[i]
  end
  return after
end

function M.git(task, root, lines, callback)
  local size = 0
  for i, line in ipairs(lines) do
    size = size + #line
    if i > 10000 or size > 1024 * 1024 then
      callback({})
      return
    end
  end
  local documents = require("git_tools.diff.model").parse(lines, { word_diff = false }).documents
  local groups, order = {}, {}
  for i = 1, #documents, 2 do
    local before, after = documents[i], documents[i + 1]
    if not groups[before.section] then
      groups[before.section] = {}
      order[#order + 1] = before.section
    end
    table.insert(groups[before.section], { before, after })
  end
  local sources, index, remaining = {}, 0, 200000
  local function next_source()
    if task.cancelled then
      return
    end
    index = index + 1
    local section = order[index]
    if not section or index > 64 or remaining <= 0 then
      callback(sources)
      return
    end
    local hunks = groups[section]
    local old = hunks[1][1]
    local function capture(err, text)
      if not err and #text <= remaining then
        remaining = remaining - #text
        local before = git.lines(text)
        local after = project(before, hunks)
        if after then
          sources[section] = { before = before, after = after }
        end
      end
      next_source()
    end
    if old.path == "/dev/null" or old.oid and old.oid:match("^0+$") then
      capture(nil, "")
    elseif old.oid then
      -- Check size before requesting blob contents; huge files keep snippets.
      git.run(task, root, { "cat-file", "-s", old.oid }, function(err, size)
        if err or not tonumber(size) or tonumber(size) > remaining then
          next_source()
        else
          git.run(task, root, { "cat-file", "blob", old.oid }, capture)
        end
      end)
    else
      next_source()
    end
  end
  next_source()
end
return M
