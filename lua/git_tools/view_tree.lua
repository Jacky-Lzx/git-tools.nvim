local M = {}

local function split_path(path)
  local parent, name = path:match("^(.*)/([^/]+)$")
  return parent or "", name or path
end

local function directory_first(a, b)
  if (a.children ~= nil) ~= (b.children ~= nil) then
    return a.children ~= nil
  end
  if a.name == b.name then
    return (a.index or 0) < (b.index or 0)
  end
  local left, right = a.name:lower(), b.name:lower()
  return left == right and a.name < b.name or left < right
end

function M.build(items)
  local root = { depth = -1, children = {} }
  local directories = { [""] = root }
  local function directory(path)
    if not directories[path] then
      local parent_path, name = split_path(path)
      local parent = directory(parent_path)
      local node = { name = name, path = path, depth = parent.depth + 1, children = {} }
      directories[path] = node
      parent.children[#parent.children + 1] = node
    end
    return directories[path]
  end

  for index, item in ipairs(items) do
    local parent_path, name = split_path(item.path)
    local parent = directory(parent_path)
    parent.children[#parent.children + 1] = { name = name, path = item.path, depth = parent.depth + 1, index = index }
  end
  for _, node in pairs(directories) do
    table.sort(node.children, directory_first)
  end
  return root
end

function M.rows(root, collapsed)
  local rows, file_rows = {}, {}
  local function walk(parent)
    for _, node in ipairs(parent.children) do
      rows[#rows + 1] = node
      if node.index then
        file_rows[node.index] = #rows
      elseif not collapsed[node.path] then
        walk(node)
      end
    end
  end
  walk(root)
  return rows, file_rows
end

return M
