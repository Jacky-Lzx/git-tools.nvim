local M = { name = "git-tools-nvim" }

-- Delta assigns TextMate scopes using bat's language grammars.
local scopes = {
  { "comment", "@comment", "Comment" },
  { "string", "@string", "String" },
  { "string.regexp", "@string.regexp", "String" },
  { "constant.character.escape", "@string.escape", "SpecialChar" },
  { "constant.numeric", "@number", "Number" },
  { "constant.language", "@constant.builtin", "Constant" },
  { "constant.language.boolean", "@boolean", "Boolean" },
  { "variable.other.constant", "@constant", "Constant" },
  { "keyword, storage", "@keyword", "Keyword" },
  { "keyword.control.conditional", "@keyword.conditional", "Conditional" },
  { "keyword.control.loop", "@keyword.repeat", "Repeat" },
  { "keyword.operator", "@operator", "Operator" },
  { "keyword.control.import", "@keyword.import", "Include" },
  { "entity.name.function, variable.function", "@function", "Function" },
  { "support.function", "@function.builtin", "Function" },
  { "entity.name.type, support.type, support.class", "@type", "Type" },
  { "variable.parameter", "@variable.parameter", "Identifier" },
  { "variable.other.member", "@variable.member", "Identifier" },
  { "variable.language", "@variable.builtin", "Special" },
  { "variable", "@variable", "Identifier" },
  { "punctuation.separator, punctuation.terminator", "@punctuation.delimiter", "Delimiter" },
  { "punctuation.section", "@punctuation.bracket", "Delimiter" },
}

local function highlight(name)
  local seen = {}
  while name and not seen[name] do
    seen[name] = true
    -- Follow global definitions without applying the current window's winhighlight.
    local hl = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
    if not hl.link then
      return hl
    end
    name = hl.link
  end
  return {}
end

function M.source(colors)
  local lines = {
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<plist version="1.0"><dict><key>settings</key><array>',
    "<dict><key>settings</key><dict><key>foreground</key><string>"
      .. colors.ui.fg
      .. "</string><key>background</key><string>"
      .. colors.palette.bg
      .. "</string></dict></dict>",
  }

  for _, scope in ipairs(scopes) do
    local hl = highlight(scope[2])
    if next(hl) == nil then
      hl = highlight(scope[3])
    end

    local style = (hl.bold and "bold " or "") .. (hl.italic and "italic" or "")
    if hl.fg or style ~= "" then
      local foreground = hl.fg and ("<key>foreground</key><string>#%06x</string>"):format(hl.fg) or ""
      lines[#lines + 1] = (
        "<dict><key>scope</key><string>%s</string><key>settings</key><dict>%s"
        .. "<key>fontStyle</key><string>%s</string></dict></dict>"
      ):format(scope[1], foreground, vim.trim(style))
    end
  end

  lines[#lines + 1] = "</array></dict></plist>"
  return lines
end

function M.list(delta, opts, env)
  local result = vim
    .system({ delta, "--list-syntax-themes" }, { cwd = opts.cwd, env = env or opts.env, text = true })
    :wait(2000)
  local names = {}
  if result.code == 0 then
    for line in (result.stdout or ""):gmatch("[^\n]+") do
      names[line:match("\t(.*)$") or line] = true
    end
  end
  return names
end

function M.build(bat, delta, source, opts, root)
  local assets = root .. "/" .. vim.fn.sha256(table.concat(source, "\n"))
  local cache = assets .. "/cache"
  if vim.uv.fs_stat(cache) then
    return cache
  end

  local ok = pcall(function()
    local config = assets .. "/config"
    assert(vim.fn.mkdir(config .. "/themes", "p", 448) == 1)
    assert(vim.fn.writefile(source, config .. "/themes/" .. M.name .. ".tmTheme") == 0)

    local original = vim.system({ bat, "--config-dir" }, { cwd = opts.cwd, env = opts.env, text = true }):wait(2000)
    local directory = vim.trim(original.stdout or "")
    if original.code == 0 and directory ~= "" then
      directory = vim.startswith(directory, "/") and directory or opts.cwd .. "/" .. directory
      if vim.fn.isdirectory(directory .. "/syntaxes") == 1 then
        assert(vim.uv.fs_symlink(directory .. "/syntaxes", config .. "/syntaxes"))
      end
    end

    -- Delta resolves bat's assets via XDG_CACHE_HOME. Keep that override inside its wrapper.
    local env = vim.tbl_extend("force", {}, opts.env or {}, {
      BAT_CONFIG_DIR = config,
      BAT_CACHE_PATH = cache .. "/bat",
      XDG_CACHE_HOME = cache,
    })
    local result = vim.system({ bat, "cache", "--build" }, { cwd = opts.cwd, env = env, text = true }):wait(2000)
    assert(result.code == 0 and M.list(delta, opts, env)[M.name])
  end)

  if ok then
    return cache
  end
  vim.fn.delete(assets, "rf")
end

return M
