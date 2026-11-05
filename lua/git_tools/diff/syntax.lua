local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("GitToolsDiffSyntax")

function M.paint(buf, documents, opts, project)
  opts = type(opts) == "string" and { ft = opts } or opts or {}
  local remaining, bytes = 30000, 200000
  for index, doc in ipairs(documents) do
    if index > 128 or bytes <= 0 or remaining <= 0 then
      break
    end
    local filetype = opts.ft ~= "" and opts.ft or nil
    filetype = filetype or doc.ft ~= "" and doc.ft or nil
    filetype = filetype or doc.path and vim.filetype.match({ filename = doc.path })
    local lang = filetype and vim.treesitter.language.get_lang(filetype)
    local size = 0
    for _, line in ipairs(doc.lines) do
      size = size + #line + 1
      if size > bytes then
        break
      end
    end
    if size <= bytes then
      bytes = bytes - size
      local text = table.concat(doc.lines, "\n")
      local function mark(row, first, last, group, priority)
        if remaining <= 0 then
          return
        end
        local target = doc.rows[row + 1]
        if target and project then
          target, first, last = project(doc, target, first, last)
        end
        local targets = type(target) == "table" and target or target and { { target, first, last } } or {}
        for _, span in ipairs(targets) do
          if remaining > 0 and span[3] > span[2] then
            api.nvim_buf_set_extmark(buf, ns, span[1] - 1, span[2], {
              end_col = span[3],
              hl_group = group,
              -- Inline change emphasis always remains above source decorations.
              priority = math.min(149, priority),
            })
            remaining = remaining - 1
          end
        end
      end
      local parser
      -- No source buffers, LSP clients or file reads are needed for highlighting.
      pcall(function()
        if not lang then
          return
        end
        parser = vim.treesitter.get_string_parser(text, lang)
        -- Include injected languages (Markdown inline/HTML, fenced code, etc.).
        -- A nil range only parses the root tree on current Neovim versions.
        parser:parse(true)
        parser:for_each_tree(function(tree, language)
          local query = vim.treesitter.query.get(language:lang(), "highlights")
          if not query then
            return
          end
          for id, node, metadata in query:iter_captures(tree:root(), text, 0, -1) do
            if remaining <= 0 then
              break
            end
            local name = query.captures[id]
            if name:sub(1, 1) ~= "_" and name ~= "spell" and name ~= "nospell" then
              local range = vim.treesitter.get_range(node, text, metadata[id])
              for line = range[1] + 1, math.min(#doc.lines, range[4] + 1) do
                local first = line == range[1] + 1 and range[2] or 0
                local last = line == range[4] + 1 and range[5] or #doc.lines[line]
                mark(
                  line - 1,
                  first,
                  last,
                  "@" .. name .. "." .. language:lang(),
                  tonumber((metadata[id] or {}).priority or metadata.priority) or 100
                )
                if remaining <= 0 then
                  break
                end
              end
            end
          end
        end)
      end)
      if parser then
        parser:destroy()
      end
      -- Only full documents have reliable nesting. Providers return source byte
      -- ranges; this renderer owns projection and the total highlight budget.
      if doc.full and opts.decorations ~= false and remaining > 0 then
        local provider = opts.highlights or require("git_tools.integrations.pairs").highlights
        pcall(function()
          for _, span in ipairs(provider(doc.lines, filetype) or {}) do
            if remaining <= 0 then
              break
            end
            mark(span.row, span.col, span.end_col, span.hl_group, span.priority or 110)
          end
        end)
      end
    end
  end
end

return M
