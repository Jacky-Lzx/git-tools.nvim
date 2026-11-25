local M = {}
local initialized, subscribed = false, false
local api = vim.api

local color = require("base_tools.color")
local highlight = require("base_tools.highlight")

local function highlight_color(name, field)
  local value = highlight.resolve(name)[field]
  return value and color.hex(value) or nil
end

local function apply(c)
  local bg = c.palette.bg
  -- Keep syntax foregrounds intact, including themes whose DiffAdd uses reverse.
  local groups = {
    Add = { bg = color.mix(c.git.add, bg, 0.10) },
    Delete = { bg = color.mix(c.git.delete, bg, 0.13) },
    Change = { bg = color.mix(c.ui.accent, bg, 0.08) },
    Text = { bg = color.mix(c.ui.accent, bg, 0.24), bold = true },
    Filler = { fg = c.ui.muted, bg = bg },
    AddText = { bg = color.mix(c.git.add, bg, 0.48), bold = true, underline = true },
    DeleteText = { bg = color.mix(c.git.delete, bg, 0.50), bold = true, underline = true },
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
    Directory = { fg = c.ui.accent },
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
  local normal_bg = highlight_color("Normal", "bg")
  local light = vim.o.background == "light"

  apply({
    palette = { bg = normal_bg or (light and "#ffffff" or "#14161b") },
    ui = {
      fg = highlight_color("Normal", "fg") or (light and "#14161b" or "#e0e2ea"),
      sidebar_bg = normal_bg or "NONE",
      cursorline_bg = highlight_color("CursorLine", "bg") or "NONE",
      muted = highlight_color("Comment", "fg") or "#808080",
      border = highlight_color("FloatBorder", "fg") or "#808080",
      accent = highlight_color("Function", "fg") or "#61afef",
    },
    git = {
      add = highlight_color("Added", "fg") or highlight_color("diffAdded", "fg") or "#98c379",
      change = highlight_color("Changed", "fg") or highlight_color("diffChanged", "fg") or "#d7ba7d",
      delete = highlight_color("Removed", "fg") or highlight_color("diffRemoved", "fg") or "#e05f65",
    },
    diagnostic = { error = highlight_color("DiagnosticError", "fg") or "#e05f65" },
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

  api.nvim_win_call(win, function()
    -- Keep the mappings when the comparison pane switches buffers.
    vim.opt.winhighlight:append(mappings)
  end)
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
