local M = {}

-- Reorder each hunk into complete before/after blocks in the host buffer.
-- Source-byte columns stay unchanged; only syntax row projections move.
function M.layout(model)
  local rows, mapping = {}, { before = {}, after = {} }
  local hunk, before, after = nil, {}, {}
  local function push(row)
    rows[#rows + 1] = row
  end
  local function side(name, entries)
    push({ kind = "hunk", text = (name == "before" and "Before  " or "After  ") .. hunk.text })
    if #entries == 0 then
      push({ kind = "meta", text = "(empty)" })
    end
    for _, entry in ipairs(entries) do
      local row = vim.tbl_extend("force", {}, entry.row)
      row[name == "before" and "new" or "old"] = nil
      push(row)
      mapping[name][entry.index] = #rows
    end
  end
  local function flush()
    if hunk then
      side("before", before)
      side("after", after)
    end
    hunk, before, after = nil, {}, {}
  end
  for index, row in ipairs(model.rows) do
    if row.kind == "hunk" then
      flush()
      hunk = row
    elseif hunk and (row.old or row.new) then
      if row.old then
        before[#before + 1] = { row = row, index = index }
      end
      if row.new then
        after[#after + 1] = { row = row, index = index }
      end
    elseif hunk and row.text:match("^\\ No newline") then
      local previous = model.rows[index - 1]
      if previous.old then
        before[#before + 1] = { row = row, index = index }
      end
      if previous.new then
        after[#after + 1] = { row = row, index = index }
      end
    else
      flush()
      push(row)
    end
  end
  flush()
  local documents = {}
  for _, doc in ipairs(model.documents) do
    local projected = vim.tbl_extend("force", {}, doc, { rows = {} })
    for line, row in pairs(doc.rows) do
      projected.rows[line] = mapping[doc.side][row] or false
    end
    documents[#documents + 1] = projected
  end
  return { rows = rows, documents = documents }
end

return M
