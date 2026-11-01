-- Pure hunk projection: source/index and destination/buffer, including ranges.
local M = {}

function M.text(text)
  local crlf = text:find("\r\n", 1, true) ~= nil
  text = text:gsub("\r\n", "\n")
  local eol = text:sub(-1) == "\n"
  local lines = text == "" and {} or vim.split(eol and text:sub(1, -2) or text, "\n", { plain = true })
  return { text = text, lines = lines, eol = eol, crlf = crlf }
end

function M.serialize(lines, eol, crlf)
  return table.concat(lines, crlf and "\r\n" or "\n") .. (eol and #lines > 0 and (crlf and "\r\n" or "\n") or "")
end

function M.diff(before, after)
  local result = (vim.text and vim.text.diff or vim.diff)(
    before.text,
    after.text,
    { result_type = "indices", algorithm = "histogram" }
  )
  local hunks = {}
  for _, h in ipairs(result) do
    hunks[#hunks + 1] = {
      old_start = h[1],
      old_count = h[2],
      new_start = h[3],
      new_count = h[4],
      old0 = h[2] == 0 and h[1] or h[1] - 1,
      new0 = h[4] == 0 and h[3] or h[3] - 1,
    }
  end
  return hunks
end

function M.bounds(h)
  local first = math.max(1, h.new_start)
  return first, math.max(first, h.new_start + h.new_count - 1)
end

function M.project(before, after, hunks, range, reverse)
  local source = reverse and after or before
  local lines = vim.deepcopy(source.lines)
  local edits, eof = {}, false
  for _, h in ipairs(hunks) do
    local first, last = M.bounds(h)
    if not range or (range[1] <= last and range[2] >= first) then
      local a, b = 0, h.new_count
      if range and h.new_count > 0 then
        a = math.max(0, range[1] - first)
        b = math.min(h.new_count, range[2] - first + 1)
      end
      local old_a = math.min(a, h.old_count)
      local old_b = b == h.new_count and h.old_count or math.min(b, h.old_count)
      local values = {}
      local from = reverse and before.lines or after.lines
      local start = reverse and h.old0 + old_a or h.new0 + a
      local count = reverse and old_b - old_a or b - a
      for i = start + 1, start + count do
        values[#values + 1] = from[i]
      end
      edits[#edits + 1] = {
        start = reverse and h.new0 + a or h.old0 + old_a,
        count = reverse and b - a or old_b - old_a,
        values = values,
      }
      if h.new0 + b >= #after.lines then
        eof = true
      end
    end
  end
  for i = #edits, 1, -1 do
    local edit = edits[i]
    for _ = 1, edit.count do
      table.remove(lines, edit.start + 1)
    end
    for j = #edit.values, 1, -1 do
      table.insert(lines, edit.start + 1, edit.values[j])
    end
  end
  local eol = source.eol
  if eof then
    eol = (reverse and before or after).eol
  end
  return M.text(M.serialize(lines, eol, false)), #edits
end

-- Preserve Git's C-quoted patch labels for whitespace/control characters.
local function label(path)
  if not path:find('[\n\r\t"\\ ]') then
    return path
  end
  return '"' .. path:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t") .. '"'
end

function M.patch(path, before, after, old_exists, new_exists, mode)
  local old, new = "a/" .. path, "b/" .. path
  local lines = { "diff --git " .. label(old) .. " " .. label(new) }
  if not old_exists then
    lines[#lines + 1] = "new file mode " .. (mode or "100644")
  end
  if not new_exists then
    lines[#lines + 1] = "deleted file mode " .. (mode or "100644")
  end
  local diff = require("git_tools.diff").unified(before, after, {
    old_path = old_exists and label(old) or "/dev/null",
    new_path = new_exists and label(new) or "/dev/null",
    context = 3,
  })
  vim.list_extend(lines, diff)
  return table.concat(lines, "\n") .. "\n"
end

return M
