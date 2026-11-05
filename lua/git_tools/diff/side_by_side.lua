-- A two-column frame inside the host's existing window. No child windows or
-- extra buffers are needed, so picker focus and frame ownership stay with it.
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("GitToolsDiff")
local syntax_ns = api.nvim_create_namespace("GitToolsDiffSyntax")
local border_ns = api.nvim_create_namespace("GitToolsDiffBorders")
local frames = {}

-- Expand tabs and clip by display cells, retaining a source-byte projection for
-- syntax and word spans. Combining characters stay with their base character.
local function fit(text, width, tabstop)
  local parts, columns, bytes, source, offsets = {}, 0, 0, 0, { [0] = 0 }
  local count, clipped = vim.fn.strchars(text, true), false
  local sizes = {}
  for i = 0, count - 1 do
    local char = vim.fn.strcharpart(text, i, 1, true)
    local cells = char == "\t" and (tabstop - columns % tabstop) or vim.fn.strdisplaywidth(char)
    if columns + cells > width then
      clipped = true
      break
    end
    local rendered = char == "\t" and string.rep(" ", cells) or char
    parts[#parts + 1] = rendered
    sizes[#sizes + 1] = cells
    for byte = 1, #char do
      offsets[source + byte] = bytes + (char == "\t" and #rendered or byte)
    end
    source, bytes, columns = source + #char, bytes + #rendered, columns + cells
  end
  if clipped then
    while columns >= width and #parts > 0 do
      columns, bytes = columns - sizes[#parts], bytes - #parts[#parts]
      parts[#parts] = nil
    end
    parts[#parts + 1] = "…"
    columns = columns + 1
  end
  local visible = bytes
  parts[#parts + 1] = string.rep(" ", math.max(0, width - columns))
  return table.concat(parts), function(col)
    return math.min(offsets[col] or visible, visible)
  end
end

-- Split into display-cell chunks without losing source bytes. Tabs retain
-- their original tab stops; combining characters stay with their base.
local function segments(text, width, tabstop, wrap, limit)
  if not wrap then
    local rendered, project = fit(text, width, tabstop)
    return { { text = rendered, project = project, first = 0, last = #text } }
  end
  local result, parts, offsets = {}, {}, { [0] = 0 }
  local columns, cells, source, bytes, first = 0, 0, 0, 0, 0
  local function flush()
    local mapping, visible = offsets, bytes
    result[#result + 1] = {
      text = table.concat(parts) .. string.rep(" ", width - cells),
      first = first,
      last = source,
      project = function(col)
        return mapping[col] or visible
      end,
    }
    parts, cells, bytes, first = {}, 0, 0, source
    offsets = { [source] = 0 }
  end
  for i = 0, vim.fn.strchars(text, true) - 1 do
    if #result >= limit then
      return result, true
    end
    local char = vim.fn.strcharpart(text, i, 1, true)
    local size = char == "\t" and tabstop - columns % tabstop or vim.fn.strdisplaywidth(char)
    -- Expand a tab before splitting, including tabs wider than a column.
    if char == "\t" then
      local remaining = size
      offsets[source] = bytes
      while remaining > 0 do
        if cells == width then
          flush()
          if #result >= limit then
            return result, true
          end
        end
        local count = math.min(remaining, width - cells)
        parts[#parts + 1] = string.rep(" ", count)
        cells, bytes, remaining = cells + count, bytes + count, remaining - count
      end
    else
      if cells + size > width and cells > 0 then
        flush()
        if #result >= limit then
          return result, true
        end
      end
      -- At least two cells are required to render wide Unicode safely.
      parts[#parts + 1] = char
      for byte = 1, #char do
        offsets[source + byte] = bytes + byte
      end
      cells, bytes = cells + size, bytes + #char
    end
    columns, source = columns + size, source + #char
    offsets[source] = bytes
  end
  if #parts > 0 or #result == 0 then
    flush()
  end
  return result
end

local function rows(model)
  local result, deleted, added, notes = {}, {}, {}, {}
  local function push(left, right)
    result[#result + 1] = { left = left, right = right }
  end
  local function flush()
    local i, j = 1, 1
    local function until_pair(a, b)
      while i < a or j < b do
        push(i < a and deleted[i] or nil, j < b and added[j] or nil)
        if i < a then
          i = i + 1
        end
        if j < b then
          j = j + 1
        end
      end
    end
    local indices = {}
    for index, row in ipairs(added) do
      indices[row] = index
    end
    for index, row in ipairs(deleted) do
      local partner = indices[row.pair]
      if partner then
        until_pair(index, partner)
        push(row, row.pair)
        i, j = index + 1, partner + 1
      end
    end
    until_pair(#deleted + 1, #added + 1)
    for _, note in ipairs(notes) do
      result[#result + 1] = { heading = note }
    end
    deleted, added, notes = {}, {}, {}
  end
  for index, row in ipairs(model.rows) do
    row.index = index
    if row.kind == "delete" then
      deleted[#deleted + 1] = row
    elseif row.kind == "add" then
      added[#added + 1] = row
    elseif row.text:match("^\\ No newline") and (#deleted > 0 or #added > 0) then
      local previous = model.rows[index - 1]
      notes[#notes + 1] = {
        kind = "meta",
        text = (previous.kind == "delete" and "Before: " or "After: ") .. row.text,
      }
    else
      flush()
      if row.kind == "context" then
        push(row, row)
      else
        result[#result + 1] = { heading = row }
      end
    end
  end
  flush()
  return result
end

local function draw(buf, frame, width)
  width = math.max(1, width)
  local gutter = frame.opts.line_numbers == false and 2 or frame.digits + 3
  local left_width = math.floor((width - 3) / 2)
  local right_width = width - 3 - left_width
  local text, marks, projection, hunks = {}, {}, { before = {}, after = {} }, {}
  local function mark(row, col, detail)
    marks[#marks + 1] = { row, col, detail }
  end
  local function heading(value, kind)
    text[#text + 1] = (fit(value, width, frame.tabstop)):gsub(" +$", "")
    mark(#text - 1, 0, { end_col = #text[#text], hl_group = "GitToolsDiff" .. kind })
  end
  -- Fall back to unified on genuinely unusable widths rather than displaying
  -- one side outside the host window.
  if width < 2 * (gutter + (frame.opts.wrap and 2 or 1)) + 3 then
    return false
  end
  heading((fit("Before", left_width, frame.tabstop)) .. " │ After", "File")
  for _, row in ipairs(frame.rows) do
    if #text >= 10000 then
      heading("… wrapped diff preview truncated (10,000 rows)", "Meta")
      break
    end
    if row.heading then
      local item = row.heading
      heading(item.text, item.kind == "file" and "File" or item.kind == "hunk" and "Hunk" or "Meta")
      if item.kind == "hunk" then
        hunks[#hunks + 1] = #text - 1
      end
    else
      local left_parts, left_truncated =
        segments(row.left and row.left.text or "", left_width - gutter, frame.tabstop, frame.opts.wrap, 10000 - #text)
      local right_parts, right_truncated = segments(
        row.right and row.right.text or "",
        right_width - gutter,
        frame.tabstop,
        frame.opts.wrap,
        10000 - #text
      )
      for part = 1, math.max(#left_parts, #right_parts) do
        local left_part, right_part = left_parts[part], right_parts[part]
        local left = left_part and left_part.text or string.rep(" ", left_width - gutter)
        local right = right_part and right_part.text or string.rep(" ", right_width - gutter)
        text[#text + 1] = left .. right
        local target = #text
        local function side(item, name, offset, finish, segment)
          local kind = name == "before" and "Delete" or "Add"
          local changed = item and item.kind ~= "context"
          local number = part == 1 and item and (name == "before" and item.old or item.new)
          local chunks = {}
          if frame.opts.line_numbers ~= false then
            chunks[#chunks + 1] = {
              string.format("%" .. frame.digits .. "s ", number or ""),
              changed and "GitToolsDiff" .. kind .. "Number" or "GitToolsDiffNumber",
            }
          end
          chunks[#chunks + 1] = {
            changed and (name == "before" and "- " or "+ ") or "  ",
            changed and "GitToolsDiff" .. kind .. "Number" or "GitToolsDiffNumber",
          }
          if name == "after" then
            table.insert(chunks, 1, { " │ ", "GitToolsDiffBorder" })
          end
          mark(target - 1, offset, { virt_text = chunks, virt_text_pos = "inline" })
          if not item or not segment then
            return
          end
          local project = segment.project
          local projected = projection[name][item.index] or {}
          projection[name][item.index] = projected
          projected[#projected + 1] = { row = target, offset = offset, segment = segment }
          if changed then
            mark(target - 1, offset, { end_col = finish, hl_group = "GitToolsDiff" .. kind, priority = 90 })
            for _, range in ipairs(item.emphasis or {}) do
              local first, last = project(math.max(segment.first, range[1])), project(math.min(segment.last, range[2]))
              if range[2] <= segment.first or range[1] >= segment.last then
                last = first
              end
              if last > first then
                mark(target - 1, offset + first, {
                  end_col = offset + last,
                  hl_group = "GitToolsDiff" .. kind .. "Text",
                  priority = 150,
                })
              end
            end
          end
        end
        side(row.left, "before", 0, #left, left_part)
        side(row.right, "after", #left, #left + #right, right_part)
      end
      if left_truncated or right_truncated then
        heading("… wrapped diff preview truncated (10,000 rows)", "Meta")
        break
      end
    end
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, syntax_ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, border_ns, 0, -1)
  api.nvim_buf_set_lines(buf, 0, -1, false, text)
  for _, item in ipairs(marks) do
    api.nvim_buf_set_extmark(buf, ns, item[1], item[2], item[3])
  end
  if frame.opts.syntax ~= false then
    require("git_tools.diff.syntax").paint(buf, frame.model.documents, frame.opts, function(doc, row, first, last)
      local targets = {}
      for _, target in ipairs(projection[doc.side][row] or {}) do
        local segment = target.segment
        if last > segment.first and first < segment.last then
          targets[#targets + 1] = {
            target.row,
            target.offset + segment.project(math.max(first, segment.first)),
            target.offset + segment.project(math.min(last, segment.last)),
          }
        end
      end
      return targets
    end)
  end
  for _, row in ipairs(hunks) do
    api.nvim_buf_set_extmark(buf, border_ns, row, 0, {
      virt_lines = { { { string.rep("─", width), "GitToolsDiffBorder" } } },
    })
  end
  vim.b[buf].git_tools_diff_hunks = hunks
  vim.b[buf].git_tools_diff_columns = true
  vim.bo[buf].modifiable = false
  frame.width = width
  return true
end

function M.prepare(model, opts, width)
  local buf = api.nvim_create_buf(false, true)
  local frame = { model = model, rows = rows(model), opts = opts, digits = 1, tabstop = vim.bo[buf].tabstop }
  for _, row in ipairs(model.rows) do
    frame.digits = math.max(frame.digits, #tostring(row.old or 0), #tostring(row.new or 0))
  end
  local ok, err = pcall(function()
    vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "hide", false
    vim.bo[buf].filetype = "git-tools-diff"
    vim.b[buf].git_tools_diff = true
    vim.b[buf].git_tools_diff_layout = "side_by_side"
    frames[buf] = frame
    api.nvim_buf_attach(buf, false, {
      on_detach = function()
        frames[buf] = nil
      end,
    })
    M.resize(buf, width)
  end)
  if not ok then
    api.nvim_buf_delete(buf, { force = true })
    error(err)
  end
  return buf
end

function M.resize(buf, width)
  local frame = frames[buf]
  if frame and frame.width ~= width then
    local views = {}
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      views[win] = api.nvim_win_call(win, vim.fn.winsaveview)
    end
    if not draw(buf, frame, width) then
      require("git_tools.diff.native").paint(buf, frame.model, frame.opts, width)
      vim.b[buf].git_tools_diff_columns = false
      frame.width = width
    end
    for win, view in pairs(views) do
      if api.nvim_win_is_valid(win) then
        api.nvim_win_call(win, function()
          vim.fn.winrestview(view)
        end)
      end
    end
  end
end

function M.set_wrap(buf, wrap, width)
  local frame = frames[buf]
  if frame and frame.opts.wrap ~= wrap then
    frame.opts = vim.tbl_extend("force", {}, frame.opts, { wrap = wrap })
    frame.width = nil
    M.resize(buf, width)
  end
end

return M
