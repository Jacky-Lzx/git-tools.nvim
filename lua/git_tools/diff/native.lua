local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("GitToolsDiff")
local border_ns = api.nvim_create_namespace("GitToolsDiffBorders")

function M.resize(buf, width)
  api.nvim_buf_clear_namespace(buf, border_ns, 0, -1)
  for _, row in ipairs(vim.b[buf].git_tools_diff_hunks or {}) do
    api.nvim_buf_set_extmark(buf, border_ns, row, 0, {
      virt_lines = { { { string.rep("─", math.max(1, width)), "GitToolsDiffBorder" } } },
    })
  end
end

function M.prepare(lines, opts, width, sources)
  opts = opts or {}
  require("git_tools.diff.theme").setup()
  local limited, size, truncated = {}, 0, false
  for i, line in ipairs(lines) do
    size = size + #line
    if i > 10000 or size > 1024 * 1024 then
      truncated = true
      break
    end
    limited[#limited + 1] = line
  end
  local model = require("git_tools.diff.model").parse(limited, opts, sources)
  if truncated then
    model.rows[#model.rows + 1] = { kind = "meta", text = "… diff preview truncated (10,000 lines / 1 MiB)" }
  end
  local buf = api.nvim_create_buf(false, true)
  local ok, err = pcall(function()
    vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "hide", false
    local text, digits = {}, 1
    local hunks = {}
    for i, row in ipairs(model.rows) do
      text[i] = row.text
      digits = math.max(digits, #tostring(row.old or 0), #tostring(row.new or 0))
    end
    api.nvim_buf_set_lines(buf, 0, -1, false, text)
    vim.bo[buf].filetype = "git-tools-diff"
    for i, row in ipairs(model.rows) do
      local changed = row.kind == "add" or row.kind == "delete"
      local kind = row.kind == "add" and "Add" or "Delete"
      if changed then
        api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
          end_row = i,
          end_col = 0,
          hl_group = "GitToolsDiff" .. kind,
          hl_eol = true,
          priority = 90,
        })
        for _, range in ipairs(row.emphasis or {}) do
          api.nvim_buf_set_extmark(buf, ns, i - 1, range[1], {
            end_col = range[2],
            hl_group = "GitToolsDiff" .. kind .. "Text",
            priority = 150,
          })
        end
      end
      if row.old or row.new then
        local gutter = {}
        if opts.line_numbers ~= false then
          local function number(value)
            return string.rep(" ", digits - #(value and tostring(value) or "")) .. (value or "")
          end
          gutter = {
            { number(row.old), row.kind == "delete" and "GitToolsDiffDeleteNumber" or "GitToolsDiffNumber" },
            { " ", "GitToolsDiffNumber" },
            { number(row.new), row.kind == "add" and "GitToolsDiffAddNumber" or "GitToolsDiffNumber" },
            { " │ ", "GitToolsDiffBorder" },
          }
        end
        gutter[#gutter + 1] = {
          row.kind == "add" and "+ " or row.kind == "delete" and "- " or "  ",
          changed and ("GitToolsDiff" .. kind .. "Number") or "GitToolsDiffNumber",
        }
        api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { virt_text = gutter, virt_text_pos = "inline" })
      else
        local group = row.kind == "hunk" and "Hunk" or row.kind == "file" and "File" or "Meta"
        api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #row.text, hl_group = "GitToolsDiff" .. group })
        if row.kind == "hunk" then
          hunks[#hunks + 1] = i - 1
        end
      end
    end
    if opts.syntax ~= false then
      require("git_tools.diff.syntax").paint(buf, model.documents, opts)
    end
    vim.b[buf].git_tools_diff = true
    vim.b[buf].git_tools_diff_hunks = hunks
    M.resize(buf, width)
    vim.bo[buf].modifiable = false
  end)
  if not ok then
    api.nvim_buf_delete(buf, { force = true })
    error(err)
  end
  return buf, truncated
end

return M
