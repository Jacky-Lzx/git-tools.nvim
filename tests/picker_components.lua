vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.getcwd() .. "/../selection-tools.nvim")
local api = vim.api
local selection = require("selection_tools")
selection.setup({
  matcher = { backend = "native" },
  component_defaults = { path = { hl = "Special" }, time = { hl = "String" } },
})
local function ready(p)
  assert(
    vim.wait(5000, function()
      return not p.loading and not p.matching
    end, 5),
    "picker did not settle"
  )
  assert(not p.error, p.error)
end
local function spans(p, group)
  local result = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(p.list_buf, -1, 0, -1, { details = true })) do
    if mark[4].hl_group == group then
      local line = api.nvim_buf_get_lines(p.list_buf, mark[2], mark[2] + 1, false)[1]
      result[#result + 1] = line:sub(mark[3] + 1, mark[4].end_col)
    end
  end
  return table.concat(result)
end
local recipes = require("git_tools.picker_components")
local path = "deep/directory/中文 needle file.lua"
local item = {
  kind = "staged",
  status = "M",
  path = path,
  file = "/repo/" .. path,
  text = "staged M " .. path,
  body = { "@@ -1 +2 @@" },
  pos = { 2, 0 },
}
local chosen
local p = selection.open({
  items = { item },
  components = recipes.for_kind("changes"),
  layout = { width = 70 },
  on_choice = function(value)
    chosen = value
  end,
})
ready(p)
assert(spans(p, "Special"):find("needle file.lua", 1, true))
p:set_query("needle")
assert(#p.matches == 1 and spans(p, "SelectionToolsMatch") == "needle")
p:confirm()
assert(chosen == item and item.file == "/repo/" .. path)
local commit =
  { sha = "1234567890abcdef", date = "2026-11-07T11:22:33+08:00", author = "中文 author", subject = "needle subject" }
p = selection.open({ items = { commit }, components = recipes.for_kind("log"), layout = { width = 70 } })
assert(spans(p, "String") == "2026-11-07")
p:set_query("2026-11-07")
assert(#p.matches == 1 and spans(p, "SelectionToolsMatch") == "2026-11-07")
p:close()
local opened, original = nil, selection.open
selection.open = function(opts)
  opened = opts
  return opts
end
local function pick(opts, extra)
  return require("git_tools.ui").pick(opts, "test", function() end, function() end, nil, extra)
end
pick(
  { picker = {
    format_item = function()
      return "legacy"
    end,
  } },
  { components = recipes.for_kind("changes") }
)
assert(opened.components == nil and opened.format_item(item) == "legacy")
pick({ picker = { components = false } })
assert(opened.components == false)
pick({ picker = { components = {} } }, { components = recipes.for_kind("changes") })
assert(#opened.components == 0)
selection.open = original
print("Git component rows: shared path/time styles, Unicode matching, source identity and overrides passed")
