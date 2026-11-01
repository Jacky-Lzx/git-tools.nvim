local api = vim.api
local M = {}
function M.blocks(lines)
  local blocks, current = {}, nil
  for i, line in ipairs(lines) do
    if line:match("^<<<<<<<+ ") then
      current = { first = i }
    elseif current and line:match("^|||||||+ ") then
      current.base = i
    elseif current and line:match("^=======+$") then
      current.separator = i
    elseif current and line:match("^>>>>>>>+ ") then
      if current.separator then
        current.last = i
        blocks[#blocks + 1] = current
      end
      current = nil
    end
  end
  return blocks
end
function M.choose(kind, buf)
  buf = buf or api.nvim_get_current_buf()
  local lines, cursor = api.nvim_buf_get_lines(buf, 0, -1, false), api.nvim_win_get_cursor(0)[1]
  for _, block in ipairs(M.blocks(lines)) do
    if cursor >= block.first and cursor <= block.last then
      local result = {}
      if kind == "ours" or kind == "both" then
        for i = block.first + 1, (block.base or block.separator) - 1 do
          result[#result + 1] = lines[i]
        end
      end
      if kind == "theirs" or kind == "both" then
        for i = block.separator + 1, block.last - 1 do
          result[#result + 1] = lines[i]
        end
      end
      api.nvim_buf_set_lines(buf, block.first - 1, block.last, false, result)
      api.nvim_win_set_cursor(0, { math.min(block.first, api.nvim_buf_line_count(buf)), 0 })
      return true
    end
  end
  return false
end
function M.nav(direction)
  local line = api.nvim_win_get_cursor(0)[1]
  local blocks = M.blocks(api.nvim_buf_get_lines(0, 0, -1, false))
  if direction == "next" then
    for _, block in ipairs(blocks) do
      if block.first > line then
        api.nvim_win_set_cursor(0, { block.first, 0 })
        return
      end
    end
  else
    for i = #blocks, 1, -1 do
      if blocks[i].first < line then
        api.nvim_win_set_cursor(0, { blocks[i].first, 0 })
        return
      end
    end
  end
end
function M.has_markers(lines)
  for _, line in ipairs(lines) do
    if line:match("^<<<<<<<+ ") or line:match("^=======+$") or line:match("^>>>>>>>+ ") or line:match("^|||||||+ ") then
      return true
    end
  end
  return false
end
return M
