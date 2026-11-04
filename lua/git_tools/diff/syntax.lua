local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("GitToolsDiffSyntax")

function M.paint(buf, documents, ft)
  local remaining, bytes = 30000, 200000
  for index, doc in ipairs(documents) do
    if index > 128 or bytes <= 0 or remaining <= 0 then
      break
    end
    local filetype = ft or doc.path and vim.filetype.match({ filename = doc.path })
    local lang = filetype and vim.treesitter.language.get_lang(filetype)
    local text = table.concat(doc.lines, "\n")
    if lang and #text <= bytes then
      bytes = bytes - #text
      -- Missing parsers/queries leave readable code with diff backgrounds.
      pcall(function()
        local parser = vim.treesitter.get_string_parser(text, lang)
        parser:parse()
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
                if remaining <= 0 then
                  break
                end
                local row = doc.rows[line]
                local first = line == range[1] + 1 and range[2] or 0
                local last = line == range[4] + 1 and range[5] or #doc.lines[line]
                if row and last > first then
                  api.nvim_buf_set_extmark(buf, ns, row - 1, first, {
                    end_col = last,
                    hl_group = "@" .. name .. "." .. language:lang(),
                    priority = math.min(140, tonumber((metadata[id] or {}).priority or metadata.priority) or 120),
                  })
                  remaining = remaining - 1
                end
              end
            end
          end
        end)
        parser:destroy()
      end)
    end
  end
end

return M
