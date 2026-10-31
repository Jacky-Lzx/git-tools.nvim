local M = {}

local function text(value)
  if type(value) == "string" then
    return value
  end
  assert(type(value) == "table" and vim.islist(value), "diff input must be a string or list of lines")
  for _, line in ipairs(value) do
    assert(type(line) == "string" and not line:find("\n", 1, true), "diff lines must be newline-free strings")
  end
  return #value > 0 and (table.concat(value, "\n") .. "\n") or ""
end

---Return unified diff lines, including labels, or {} for identical inputs.
---Strings preserve exact final newlines; line arrays represent terminated lines.
function M.unified(before, after, opts)
  opts = opts or {}
  local context = opts.context == nil and 3 or opts.context
  assert(type(context) == "number" and context >= 0 and context % 1 == 0, "diff context must be a nonnegative integer")
  local old, new = opts.old_path or "before", opts.new_path or opts.old_path or "after"
  assert(type(old) == "string" and type(new) == "string", "diff labels must be strings")
  local result = (vim.text and vim.text.diff or vim.diff)(text(before), text(after), {
    result_type = "unified",
    ctxlen = context,
  })
  if result == "" then
    return {}
  end
  local lines = { "--- " .. old, "+++ " .. new }
  vim.list_extend(lines, vim.split(result, "\n", { trimempty = true }))
  return lines
end

function M.render(view, lines, opts, valid)
  return require("git_tools.diff.render").render(view, lines, opts, valid)
end

return M
