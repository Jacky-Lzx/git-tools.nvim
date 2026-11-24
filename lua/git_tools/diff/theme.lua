local M = {}
local initialized, subscribed = false, false
local api = vim.api

local function color(name, field)
  local seen = {}
  while name and not seen[name] do
    seen[name] = true
    local hl = api.nvim_get_hl(0, { name = name, link = true, create = false })
    if not hl.link then
      return hl[field] and string.format("#%06x", hl[field]) or nil
    end
    name = hl.link
  end
end

local function mix(fg, bg, amount)
  local function channel(value, offset)
    return tonumber(value:sub(offset, offset + 1), 16)
  end
  local result = "#"
  for _, offset in ipairs({ 2, 4, 6 }) do
    result = result
      .. string.format("%02x", math.floor(channel(fg, offset) * amount + channel(bg, offset) * (1 - amount) + 0.5))
  end
  return result
end

local function apply(c)
  local bg = c.palette.bg
  -- Keep syntax foregrounds intact, including themes whose DiffAdd uses reverse.
  local groups = {
    Add = { bg = mix(c.git.add, bg, 0.10) },
    Delete = { bg = mix(c.git.delete, bg, 0.13) },
    Change = { bg = mix(c.ui.accent, bg, 0.08) },
    Text = { bg = mix(c.ui.accent, bg, 0.24), bold = true },
    Filler = { fg = c.ui.muted, bg = bg },
    AddText = { bg = mix(c.git.add, bg, 0.48), bold = true, underline = true },
    DeleteText = { bg = mix(c.git.delete, bg, 0.50), bold = true, underline = true },
    AddNumber = { fg = c.git.add },
    DeleteNumber = { fg = c.git.delete },
    Number = { fg = c.ui.muted },
    Border = { fg = c.ui.border },
    File = { fg = c.ui.fg, bold = true },
    Hunk = { fg = c.ui.accent, bold = true },
    Meta = { fg = c.ui.muted },
  }
  for name, value in pairs(groups) do
    api.nvim_set_hl(0, "GitToolsDiff" .. name, value)
  end
  local sidebar = c.ui.sidebar_bg
  for name, value in pairs({
    Normal = { fg = c.ui.fg, bg = sidebar },
    Title = { fg = c.ui.accent, bg = sidebar, bold = true },
    Selected = { bg = c.ui.cursorline_bg },
    Add = { fg = c.git.add },
    Change = { fg = c.git.change },
    Delete = { fg = c.git.delete },
    Conflict = { fg = c.diagnostic.error },
  }) do
    api.nvim_set_hl(0, "GitToolsCompare" .. name, value)
  end
end

local function fallback()
  local normal_bg = color("Normal", "bg")
  local light = vim.o.background == "light"
  apply({
    palette = { bg = normal_bg or (light and "#ffffff" or "#14161b") },
    ui = {
      fg = color("Normal", "fg") or (light and "#14161b" or "#e0e2ea"),
      sidebar_bg = normal_bg or "NONE",
      cursorline_bg = color("CursorLine", "bg") or "NONE",
      muted = color("Comment", "fg") or "#808080",
      border = color("FloatBorder", "fg") or "#808080",
      accent = color("Function", "fg") or "#61afef",
    },
    git = {
      add = color("Added", "fg") or color("diffAdded", "fg") or "#98c379",
      change = color("Changed", "fg") or color("diffChanged", "fg") or "#d7ba7d",
      delete = color("Removed", "fg") or color("diffRemoved", "fg") or "#e05f65",
    },
    diagnostic = { error = color("DiagnosticError", "fg") or "#e05f65" },
  })
end

local function attach()
  local themes = package.loaded.theme_tools
  if not subscribed and type(themes) == "table" and type(themes.on_change) == "function" then
    subscribed = true
    themes.on_change("git-tools.diff", apply)
  end
end

function M.setup()
  if initialized then
    return
  end
  initialized = true
  fallback()
  local group = api.nvim_create_augroup("GitToolsDiffTheme", { clear = true })
  api.nvim_create_autocmd("User", { group = group, pattern = "ThemeToolsReady", callback = attach })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      fallback()
      attach()
    end,
  })
  attach()
end

local function window_highlights(win, mappings)
  M.setup()
  local entries = {}
  for entry in vim.wo[win].winhighlight:gmatch("[^,]+") do
    if not mappings[entry:match("^([^:]+):")] then
      entries[#entries + 1] = entry
    end
  end
  for source, target in pairs(mappings) do
    entries[#entries + 1] = source .. ":" .. target
  end
  vim.wo[win].winhighlight = table.concat(entries, ",")
end

function M.window(win)
  window_highlights(win, {
    DiffAdd = "GitToolsDiffAdd",
    DiffDelete = "GitToolsDiffDelete",
    DiffChange = "GitToolsDiffChange",
    DiffText = "GitToolsDiffText",
    DiffTextAdd = "GitToolsDiffAddText",
    DiffTextDelete = "GitToolsDiffDeleteText",
    DiffAdded = "GitToolsDiffAdd",
    DiffRemoved = "GitToolsDiffDelete",
    DiffChanged = "GitToolsDiffChange",
    DiffFiller = "GitToolsDiffFiller",
  })
end

function M.compare_panel(win)
  window_highlights(win, {
    Normal = "GitToolsCompareNormal",
    NormalNC = "GitToolsCompareNormal",
    CursorLine = "GitToolsCompareSelected",
    WinBar = "GitToolsCompareTitle",
    WinBarNC = "GitToolsCompareTitle",
  })
end

return M
