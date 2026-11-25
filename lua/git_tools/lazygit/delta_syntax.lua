local M = { name = "git-tools-nvim" }
local entries = {}
local root, exiting

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

local function theme_names(result)
  local names = {}
  if result.code == 0 then
    for line in (result.stdout or ""):gmatch("[^\n]+") do
      names[line:match("\t(.*)$") or line] = true
    end
  end
  return names
end

function M.list(delta, opts)
  return theme_names(
    vim.system({ delta, "--list-syntax-themes" }, { cwd = opts.cwd, env = opts.env, text = true }):wait(2000)
  )
end

function M.key(bat, delta, source, opts)
  local context = { bat, delta, vim.uv.fs_realpath(bat) or bat, vim.uv.fs_realpath(delta) or delta }
  for _, name in ipairs({ "BAT_CONFIG_DIR", "BAT_CONFIG_PATH", "XDG_CONFIG_HOME", "HOME" }) do
    local value = tostring((opts.env or {})[name] or vim.env[name] or "")
    if value ~= "" and not vim.startswith(value, "/") then
      value = opts.cwd .. "/" .. value
    end
    context[#context + 1] = value
  end
  return vim.fn.sha256(vim.json.encode(context) .. table.concat(source, "\n"))
end

function M.cached(key)
  local entry = entries[key]
  return entry and entry.cache
end

local function build(entry, key, bat, delta, source, opts)
  local assets = root .. "/" .. key
  local config, cache = assets .. "/config", assets .. "/cache"

  local function finish(success)
    local callbacks = entry.callbacks
    entry.callbacks = nil
    if success then
      entry.cache = cache
    else
      entries[key] = nil
      vim.fn.delete(assets, "rf")
    end
    for callback in pairs(callbacks) do
      vim.schedule(function()
        if not exiting and callbacks[callback] then
          callback(entry.cache)
        end
      end)
    end
  end

  -- Global state and filesystem operations run on the main loop.
  local function run(argv, env, done)
    local options = { cwd = opts.cwd, env = env, text = true, timeout = 2000 }
    local ok, job = pcall(
      vim.system,
      argv,
      options,
      vim.schedule_wrap(function(result)
        entry.job = nil
        if not exiting and not pcall(done, result) then
          finish(false)
        end
      end)
    )
    if ok then
      entry.job = job
    else
      finish(false)
    end
  end

  local ok, written = pcall(function()
    return vim.fn.mkdir(config .. "/themes", "p", 448) == 1
      and vim.fn.writefile(source, config .. "/themes/" .. M.name .. ".tmTheme") == 0
  end)
  if not ok or not written then
    finish(false)
    return
  end

  -- Delta resolves bat's assets via XDG_CACHE_HOME.
  local env = vim.tbl_extend("force", {}, opts.env or {}, {
    BAT_CONFIG_DIR = config,
    BAT_CACHE_PATH = cache .. "/bat",
    XDG_CACHE_HOME = cache,
  })
  run({ bat, "--config-dir" }, opts.env, function(original)
    local directory = vim.trim(original.stdout or "")
    if original.code == 0 and directory ~= "" then
      directory = vim.startswith(directory, "/") and directory or opts.cwd .. "/" .. directory
      if vim.fn.isdirectory(directory .. "/syntaxes") == 1 then
        assert(vim.uv.fs_symlink(directory .. "/syntaxes", config .. "/syntaxes"))
      end
    end
    run({ bat, "cache", "--build" }, env, function(result)
      assert(result.code == 0)
      run({ delta, "--list-syntax-themes" }, env, function(probe)
        finish(theme_names(probe)[M.name])
      end)
    end)
  end)
end

function M.request(key, bat, delta, source, opts, callback)
  if not root then
    root = vim.fn.tempname()
    vim.api.nvim_create_autocmd("VimLeave", {
      once = true,
      callback = function()
        exiting = true
        for _, entry in pairs(entries) do
          if entry.job then
            pcall(entry.job.kill, entry.job, 9)
          end
        end
        vim.fn.delete(root, "rf")
      end,
    })
  end

  local entry = entries[key]
  if entry and entry.cache then
    local active = true
    vim.schedule(function()
      if active and not exiting then
        callback(entry.cache)
      end
    end)
    return function()
      active = false
    end
  end
  if not entry then
    entry = { callbacks = {} }
    entries[key] = entry
    vim.schedule(function()
      if not exiting then
        build(entry, key, bat, delta, source, opts)
      end
    end)
  end
  local callbacks = entry.callbacks
  callbacks[callback] = true
  return function()
    callbacks[callback] = nil
  end
end

return M
