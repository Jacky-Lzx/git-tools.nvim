local M = {}

local function chars(text)
  local values, offsets = {}, { 0 }
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    values[#values + 1] = char
    offsets[#offsets + 1] = offsets[#offsets] + #char
  end
  return values, offsets
end

-- Let Neovim's C diff engine find multiple disjoint changes. Byte offsets stay
-- on UTF-8 boundaries; neither terminal cells nor Lua bytes are characters.
function M.ranges(old, new)
  if #old > 4096 or #new > 4096 then
    return {}, {}
  end
  local a, ao = chars(old)
  local b, bo = chars(new)
  local left, right = {}, {}
  local changes = (vim.text and vim.text.diff or vim.diff)(
    table.concat(a, "\n") .. (#a > 0 and "\n" or ""),
    table.concat(b, "\n") .. (#b > 0 and "\n" or ""),
    { result_type = "indices" }
  )
  for _, h in ipairs(changes) do
    if h[2] > 0 then
      left[#left + 1] = { ao[h[1]], ao[h[1] + h[2]] }
    end
    if h[4] > 0 then
      right[#right + 1] = { bo[h[3]], bo[h[3] + h[4]] }
    end
  end
  return left, right
end

local function tokens(text)
  local counts, size = {}, 0
  for token in text:gmatch("[%w_]+") do
    counts[token] = (counts[token] or 0) + 1
    size = size + #token
  end
  -- Include non-ASCII characters so CJK-only lines can be paired too.
  for char in text:gmatch("[\194-\244][\128-\191]+") do
    counts[char] = (counts[char] or 0) + 1
    size = size + #char
  end
  return { counts = counts, size = size, text = text }
end

local function similarity(a, b)
  if a.text == b.text then
    return 1
  end
  if a.size + b.size == 0 then
    return 0
  end
  local common = 0
  for token, count in pairs(a.counts) do
    common = common + math.min(count, b.counts[token] or 0) * #token
  end
  return 2 * common / (a.size + b.size)
end

-- Monotone alignment avoids pairing every deletion with the same-position
-- insertion when a replacement block also inserts or removes complete lines.
function M.align(deleted, added, emphasis)
  local pairs = {}
  local function pair(i, j)
    table.insert(pairs, 1, { i, j })
    if emphasis ~= false then
      deleted[i].emphasis, added[j].emphasis = M.ranges(deleted[i].text, added[j].text)
    end
  end
  -- A single replacement has no competing line pairing. Token overlap can be
  -- zero for a renamed identifier or punctuation-only edit; still compare chars.
  if #deleted == 1 and #added == 1 then
    pair(1, 1)
    return pairs
  end
  if #deleted > 32 or #added > 32 then
    return pairs
  end
  local a, b, score = {}, {}, { [0] = {} }
  for i, row in ipairs(deleted) do
    a[i] = tokens(row.text:sub(1, 4096))
  end
  for j, row in ipairs(added) do
    b[j] = tokens(row.text:sub(1, 4096))
    score[0][j] = 0
  end
  score[0][0] = 0
  for i = 1, #a do
    score[i] = { [0] = 0 }
    for j = 1, #b do
      local weight = similarity(a[i], b[j]) - 0.3
      score[i][j] = math.max(score[i - 1][j], score[i][j - 1], score[i - 1][j - 1] + weight)
    end
  end
  local i, j = #a, #b
  while i > 0 and j > 0 do
    if score[i][j] == score[i - 1][j] then
      i = i - 1
    elseif score[i][j] == score[i][j - 1] then
      j = j - 1
    else
      pair(i, j)
      i, j = i - 1, j - 1
    end
  end
  return pairs
end

return M
