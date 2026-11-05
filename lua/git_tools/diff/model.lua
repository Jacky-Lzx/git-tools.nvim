local M = {}

local function path(label)
  if label:sub(1, 1) == '"' then
    label = label:match('^"(.*)"') or label
    local parts, i = {}, 1
    local escapes =
      { a = "\7", b = "\8", f = "\12", n = "\n", r = "\r", t = "\t", v = "\11", ['"'] = '"', ["\\"] = "\\" }
    while i <= #label do
      if label:sub(i, i) == "\\" then
        local octal = label:sub(i + 1, i + 3):match("^[0-3][0-7][0-7]$")
        if octal then
          parts[#parts + 1], i = string.char(tonumber(octal, 8)), i + 4
        else
          local escaped = label:sub(i + 1, i + 1)
          parts[#parts + 1], i = escapes[escaped] or ("\\" .. escaped), i + 2
        end
      else
        parts[#parts + 1], i = label:sub(i, i), i + 1
      end
    end
    label = table.concat(parts)
  else
    label = label:match("^[^\t]+") or label
  end
  if label:match("^file://") then
    label = vim.uri_to_fname(label)
  end
  return label:gsub("^[ab]/", "")
end

function M.parse(lines, opts, sources)
  opts = opts or {}
  local rows, documents = {}, {}
  local old_path, new_path, file, hunk, before, after
  local section = 0
  local old_oid, new_oid
  local old_line, new_line, old_left, new_left = 0, 0, 0, 0
  local deleted, added = {}, {}
  local function flush()
    if opts.word_diff ~= false or opts.layout == "side_by_side" then
      local pairs = require("git_tools.diff.words").align(deleted, added, opts.word_diff)
      if opts.layout == "side_by_side" then
        for _, pair in ipairs(pairs) do
          deleted[pair[1]].pair = added[pair[2]]
        end
      end
    end
    deleted, added = {}, {}
  end
  local function push(kind, text)
    local row = { kind = kind, text = text, index = #rows + 1 }
    rows[#rows + 1] = row
    return row
  end
  local function source(doc, row, paint)
    doc.lines[#doc.lines + 1] = row.text
    doc.rows[#doc.lines] = paint and row.index or false
    doc.numbers[#doc.lines] = doc.side == "before" and row.old or row.new
  end
  for _, line in ipairs(lines) do
    local a, ac, b, bc = line:match("^@@ %-(%d+)(,?%d*) %+(%d+)(,?%d*) @@")
    local marker = line:sub(1, 1)
    if a then
      flush()
      old_line, new_line = tonumber(a), tonumber(b)
      old_left, new_left = tonumber(ac:sub(2)) or 1, tonumber(bc:sub(2)) or 1
      local name = new_path ~= "/dev/null" and new_path or old_path
      hunk = push(
        "hunk",
        (name and (name:gsub("[\r\n\t]", " ") .. ":" .. (new_left > 0 and new_line or old_line) .. "  ") or "") .. line
      )
      before = {
        path = old_path,
        lines = {},
        rows = {},
        numbers = {},
        section = section,
        side = "before",
        start = old_left == 0 and old_line + 1 or old_line,
        oid = old_oid,
        count = old_left,
      }
      after = {
        path = name,
        lines = {},
        rows = {},
        numbers = {},
        section = section,
        side = "after",
        start = new_left == 0 and new_line + 1 or new_line,
        oid = new_oid,
        count = new_left,
      }
      documents[#documents + 1], documents[#documents + 2] = before, after
    elseif hunk and (old_left > 0 or new_left > 0) and (marker == " " or marker == "-" or marker == "+") then
      if marker == " " then
        flush()
      end
      local kind = marker == "-" and "delete" or marker == "+" and "add" or "context"
      local row = push(kind, line:sub(2))
      if marker ~= "+" then
        row.old = old_line
        old_line, old_left = old_line + 1, math.max(0, old_left - 1)
        source(before, row, marker == "-" or opts.layout == "side_by_side" or opts.layout == "top_bottom")
      end
      if marker ~= "-" then
        row.new = new_line
        new_line, new_left = new_line + 1, math.max(0, new_left - 1)
        source(after, row, true)
      end
      if marker == "-" then
        deleted[#deleted + 1] = row
      elseif marker == "+" then
        added[#added + 1] = row
      end
    elseif line:match("^\\ No newline") then
      push("meta", line)
    else
      flush()
      hunk = nil
      if line:match("^diff %-%-git ") then
        old_path, new_path, old_oid, new_oid = nil, nil, nil, nil
        file = push("file", line:sub(12))
      elseif line:match("^%-%-%- ") then
        old_path = path(line:sub(5))
      elseif line:match("^%+%+%+ ") then
        section = section + 1
        new_path = path(line:sub(5))
        if not file then
          file = push("file", "")
        end
        local name = new_path == "/dev/null" and old_path or new_path
        file.text = old_path
            and old_path ~= "/dev/null"
            and new_path ~= "/dev/null"
            and old_path ~= new_path
            and (old_path .. " → " .. new_path)
          or name
        file.text = file.text:gsub("[\r\n\t]", " ")
        file = nil
      elseif line:match("^index %x+%.%.%x+") then
        old_oid, new_oid = line:match("^index (%x+)%.%.(%x+)")
      else
        push("meta", line)
      end
    end
  end
  flush()
  local visible = {}
  -- Resolve source row indices again when file headers are omitted.
  local mapping = {}
  for _, row in ipairs(rows) do
    if row.kind ~= "file" or opts.file_header ~= false then
      visible[#visible + 1] = row
      mapping[row.index] = #visible
    end
  end
  for _, doc in ipairs(documents) do
    for i, row in ipairs(doc.rows) do
      doc.rows[i] = mapping[row] or false
    end
  end
  -- Validate all visible source lines before using a full snapshot. A stale or
  -- mismatched snapshot falls back for that entire side, never colors wrong text.
  local full, invalid = {}, {}
  for _, doc in ipairs(documents) do
    local source = sources and sources[doc.section]
    local lines = source and source[doc.side]
    if lines then
      local key = doc.section .. doc.side
      local target = full[key]
        or { path = doc.path, lines = lines, rows = {}, ft = source.ft, side = doc.side, full = true }
      full[key] = target
      for i, text in ipairs(doc.lines) do
        local number = doc.numbers[i]
        if lines[number] ~= text then
          invalid[key] = true
        elseif doc.rows[i] then
          target.rows[number] = doc.rows[i]
        end
      end
    end
  end
  local colored, emitted = {}, {}
  for _, doc in ipairs(documents) do
    local key = doc.section .. doc.side
    if full[key] and not invalid[key] then
      if not emitted[key] then
        colored[#colored + 1], emitted[key] = full[key], true
      end
    else
      colored[#colored + 1] = doc
    end
  end
  return { rows = visible, documents = colored }
end

return M
