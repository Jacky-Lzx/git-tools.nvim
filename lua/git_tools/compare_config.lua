local M = {}

local default_keys = { open = "<CR>", next_file = "<Tab>", refresh = "R", close = "q" }
local actions = {
  open = { order = 1, hint = "open", desc = "Open file diff or toggle folder", method = "open_panel_row" },
  next_file = { order = 2, hint = "next", desc = "Show next changed file", method = "next_file" },
  refresh = { order = 3, hint = "refresh", desc = "Refresh Git diff view", method = "refresh" },
  close = { order = 4, hint = "close", desc = "Close Git diff view", method = "close" },
}
M.actions = actions

local function resolve_binding(lhs, value)
  local chain = type(value) == "table" and value or { value }
  local entries = {}
  for index, action in pairs(chain) do
    if index ~= "desc" then
      entries[index] = action
    end
  end
  local prefix = "compare.keymap.panel[" .. lhs .. "]"
  assert(vim.islist(entries) and #entries > 0, prefix .. " must contain a nonempty action list")
  assert(chain.desc == nil or type(chain.desc) == "string" and chain.desc ~= "", prefix .. ".desc must be nonempty")

  local primary
  local hints = {}
  for _, action in ipairs(entries) do
    if type(action) == "function" then
      hints[#hints + 1] = "custom action"
    else
      local spec = actions[action]
      assert(spec, prefix .. ": unknown action " .. tostring(action))
      primary = primary or action
      hints[#hints + 1] = spec.hint
    end
  end
  local hint = chain.desc or table.concat(hints, " / ")
  local desc = chain.desc or (#entries == 1 and primary and actions[primary].desc) or "Git compare: " .. hint
  return { lhs = lhs, actions = entries, primary = primary, hint = hint, desc = desc }
end

local function resolve_panel(keymap)
  assert(type(keymap) == "table", "compare.keymap.panel must be a table")
  local bindings, used = {}, {}
  for lhs, value in pairs(keymap) do
    assert(type(lhs) == "string" and lhs ~= "", "compare.keymap.panel keys must be nonempty strings")
    if value ~= false then
      local key = vim.keycode(lhs)
      assert(not used[key], "compare.keymap.panel: duplicate mapping " .. lhs)
      used[key] = true
      bindings[#bindings + 1] = resolve_binding(lhs, value)
    end
  end
  table.sort(bindings, function(a, b)
    local left = a.primary and actions[a.primary].order or 5
    local right = b.primary and actions[b.primary].order or 5
    if left ~= right then
      return left < right
    end
    return a.lhs < b.lhs
  end)
  return bindings
end

local function legacy_panel_keymap(keys)
  local keymap = {}
  for action, default in pairs(default_keys) do
    local lhs = keys[action]
    if lhs == nil then
      lhs = default
    end
    assert(
      lhs == false or type(lhs) == "string" and lhs ~= "",
      "compare.panel_keys." .. action .. " must be a nonempty key string or false"
    )
    if lhs then
      assert(not keymap[lhs], "compare.panel_keys: duplicate mapping " .. lhs)
      keymap[lhs] = action
    end
  end
  return keymap
end

local defaults = resolve_panel(legacy_panel_keymap({}))
M.panel_keymap = defaults

function M.resolve(opts)
  assert(opts == nil or type(opts) == "table", "compare options must be a table")
  opts = opts or {}
  local keymap = opts.keymap
  assert(keymap == nil or type(keymap) == "table", "compare.keymap must be a table")
  if keymap and keymap.panel ~= nil then
    return resolve_panel(keymap.panel)
  end

  if opts.panel_keys ~= nil then
    assert(type(opts.panel_keys) == "table", "compare.panel_keys must be a table")
    return resolve_panel(legacy_panel_keymap(opts.panel_keys))
  end
  return defaults
end

function M.configure(bindings)
  M.panel_keymap = bindings or defaults
end

return M
