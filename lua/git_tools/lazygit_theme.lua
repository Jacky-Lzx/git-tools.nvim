-- Session-local configuration: never write LazyGit's or Git's user config.
local M = {}
local catppuccin_syntax = {
  mocha = "Catppuccin Mocha",
  latte = "Catppuccin Latte",
  frappe = "Catppuccin Frappe",
  macchiato = "Catppuccin Macchiato",
}

local function mix(fg, bg, amount)
  local result = "#"
  for _, offset in ipairs({ 2, 4, 6 }) do
    local a, b = tonumber(fg:sub(offset, offset + 1), 16), tonumber(bg:sub(offset, offset + 1), 16)
    result = result .. string.format("%02x", math.floor(a * amount + b * (1 - amount) + 0.5))
  end
  return result
end

local function config(c)
  local ui, p = c.ui, c.palette
  local theme = {
    activeBorderColor = { ui.accent, "bold" },
    inactiveBorderColor = { ui.border },
    searchingActiveBorderColor = { c.diagnostic.warn, "bold" },
    optionsTextColor = { ui.accent },
    selectedLineBgColor = { ui.selection_bg == "NONE" and "default" or ui.selection_bg },
    inactiveViewSelectedLineBgColor = { ui.cursorline_bg == "NONE" and "default" or ui.cursorline_bg },
    defaultFgColor = { ui.fg },
    selectedLineFgColor = { ui.selection_fg },
    unstagedChangesColor = { c.git.delete },
    cherryPickedCommitBgColor = { ui.selection_bg == "NONE" and "default" or ui.selection_bg },
    cherryPickedCommitFgColor = { ui.accent },
    markedBaseCommitBgColor = { p.yellow },
    markedBaseCommitFgColor = { p.bg },
    authorColors = { ["*"] = ui.accent },
  }
  -- Clear theme-specific overrides as well, so an existing dark/light theme
  -- cannot take precedence over the generated semantic colors.
  return { gui = { colorScheme = c.background, theme = theme, darkTheme = theme, lightTheme = theme } }
end

local function environment(opts, name)
  if opts.env and opts.env[name] ~= nil then
    return opts.env[name]
  end
  return vim.env[name]
end

local function arguments(opts)
  local args, files, directory = {}, nil, nil
  local i = 1
  while i <= #opts.args do
    local arg = opts.args[i]
    if arg == "--" then
      vim.list_extend(args, vim.list_slice(opts.args, i))
      break
    end
    local key, value = arg:match("^(%-%-?[%w%-]+)=(.*)$")
    key = key or arg
    local file = key == "--use-config-file" or key == "-ucf"
    local dir = key == "--use-config-dir" or key == "-ucd"
    if file or dir then
      if value == nil then
        i = i + 1
        value = assert(opts.args[i], "Missing value for " .. key)
      end
      if file then
        files = value
      else
        directory = value
        vim.list_extend(args, { key, value })
      end
    else
      args[#args + 1] = arg
    end
    i = i + 1
  end
  files = files and files ~= "" and files or environment(opts, "LG_CONFIG_FILE")
  if not files or files == "" then
    local env = vim.tbl_extend("force", {}, opts.env or {})
    if directory then
      env.CONFIG_DIR = directory
    end
    local result = vim
      .system({ opts.command, "--print-config-dir" }, { cwd = opts.cwd, env = env, text = true })
      :wait(2000)
    assert(result.code == 0, "Unable to locate LazyGit config: " .. (result.stderr or ""))
    local path = vim.trim(result.stdout or "") .. "/config.yml"
    assert(path ~= "/config.yml", "LazyGit returned an empty config directory")
    if not vim.startswith(path, "/") and not path:match("^%a:[/\\]") then
      path = opts.cwd .. "/" .. path
    end
    -- LazyGit creates a missing default config. An explicit config list instead
    -- rejects missing files; omit it here rather than creating a user's file.
    files = vim.fn.filereadable(path) == 1 and path or ""
  end
  return args, files
end

local function write(path, content, executable)
  local temporary = path .. ".new"
  assert(vim.fn.writefile(content, temporary) == 0, "Unable to write " .. temporary)
  if executable then
    assert(vim.uv.fs_chmod(temporary, 448)) -- 0700
  end
  assert(vim.uv.fs_rename(temporary, path))
end

local function delta(path, cwd)
  -- Respect the child's PATH, including relative entries, without a shell lookup.
  local separator = package.config:sub(1, 1) == "\\" and ";" or ":"
  for entry in (path .. separator):gmatch("(.-)" .. separator) do
    local candidate = (entry == "" and "." or entry) .. "/delta"
    if not vim.startswith(candidate, "/") then
      candidate = cwd .. "/" .. candidate
    end
    if vim.fn.executable(candidate) == 1 then
      return vim.fn.fnamemodify(candidate, ":p")
    end
  end
end

local function delta_script(command, c, syntax)
  local p, ui, git = c.palette, c.ui, c.git
  local styles = {
    ["syntax-theme"] = syntax,
    ["minus-style"] = "syntax " .. mix(git.delete, p.bg, 0.13),
    ["plus-style"] = "syntax " .. mix(git.add, p.bg, 0.10),
    ["minus-emph-style"] = "bold syntax " .. mix(git.delete, p.bg, 0.50),
    ["plus-emph-style"] = "bold syntax " .. mix(git.add, p.bg, 0.48),
    ["minus-non-emph-style"] = "minus-style",
    ["plus-non-emph-style"] = "plus-style",
    ["zero-style"] = "syntax normal",
    ["file-style"] = ui.fg,
    ["file-decoration-style"] = ui.border,
    ["hunk-header-style"] = "file line-number",
    ["hunk-header-decoration-style"] = ui.border .. " box",
    ["hunk-header-file-style"] = ui.fg .. " bold",
    ["hunk-header-line-number-style"] = ui.accent,
    ["line-numbers-left-style"] = ui.muted,
    ["line-numbers-right-style"] = ui.muted,
    ["line-numbers-zero-style"] = ui.muted,
    ["line-numbers-minus-style"] = git.delete,
    ["line-numbers-plus-style"] = git.add,
    ["commit-style"] = ui.accent,
    ["commit-decoration-style"] = ui.border .. " box",
    ["map-styles"] = "",
  }
  local names, flags, separate, equals = vim.tbl_keys(styles), {}, {}, {}
  table.sort(names)
  for _, name in ipairs(names) do
    flags[#flags + 1] = vim.fn.shellescape("--" .. name .. "=" .. styles[name])
    separate[#separate + 1], equals[#equals + 1] = "--" .. name, "--" .. name .. "=*"
  end
  -- Rotate the original argv while removing only managed color options. All
  -- other renderer arguments (hyperlinks, line numbers, etc.) remain literal.
  return {
    "#!/bin/sh",
    "remaining=$#",
    "options=true",
    'while [ "$remaining" -gt 0 ]; do',
    "  arg=$1; shift; remaining=$((remaining - 1))",
    '  if [ "$options" = false ]; then set -- "$@" "$arg"; continue; fi',
    '  case "$arg" in',
    '    --) options=false; set -- "$@" "$arg";;',
    "    " .. table.concat(separate, "|") .. ")",
    '      if [ "$remaining" -gt 0 ]; then shift; remaining=$((remaining - 1)); fi;;',
    "    " .. table.concat(equals, "|") .. ") ;;",
    '    *) set -- "$@" "$arg";;',
    "  esac",
    "done",
    "exec " .. vim.fn.shellescape(command) .. " " .. table.concat(flags, " ") .. ' "$@"',
  }
end

function M.prepare(opts)
  local themes = package.loaded.theme_tools
  if opts.theme == false or type(themes) ~= "table" or type(themes.palette) ~= "function" then
    return
  end
  local root = vim.fn.tempname()
  local state = { root = root, path = root .. "/theme.yml" }
  function state:close()
    if self.unsubscribe then
      self.unsubscribe()
    end
    vim.fn.delete(self.root, "rf")
  end
  local ok, err = pcall(function()
    assert(not root:find(",", 1, true), "LazyGit cannot use config paths containing commas")
    assert(vim.fn.mkdir(root, "p", 448) == 1, "Unable to create LazyGit theme directory")
    state.args, state.files = arguments(opts)
    state.env = vim.tbl_extend("force", {}, opts.env or {})
    state.env.LG_CONFIG_FILE = (state.files ~= "" and state.files .. "," or "") .. state.path
    local path = environment(opts, "PATH") or ""
    local command = vim.fn.has("win32") == 0 and delta(path, opts.cwd) or nil
    local syntax_themes = {}
    if command then
      local result = vim.system({ command, "--list-syntax-themes" }, { env = opts.env, text = true }):wait(2000)
      for name in (result.stdout or ""):gmatch("[^\n]+") do
        syntax_themes[name:match("\t(.*)$") or name] = true
      end
      state.env.PATH = root .. ":" .. path
    end
    function state:update(c)
      if vim.deep_equal(self.colors, c) then
        return false
      end
      if command then
        local flavour = c.name:match("catppuccin%-(%a+)$") or c.name == "theme-tools-mocha" and "mocha"
        local wanted = c.name:find("dracula") and "Dracula" or catppuccin_syntax[flavour] or "ansi"
        local syntax = syntax_themes[wanted] and wanted or syntax_themes.ansi and "ansi" or "none"
        write(root .. "/delta", delta_script(command, c, syntax), true)
      end
      write(self.path, { vim.json.encode(config(c)) })
      self.colors = vim.deepcopy(c)
      return true
    end
    function state:attach(session)
      if type(themes.on_change) == "function" then
        self.unsubscribe = themes.on_change("git-tools.lazygit." .. session.buf, function(c)
          if not session.closed and not session.exited and self:update(c) then
            -- LazyGit reloads changed config on terminal focus-in. This updates
            -- its existing process and panel state, without restarting a job.
            vim.fn.chansend(session.job, "\27[O\27[I")
          end
        end)
      end
    end
    state:update(themes.palette())
  end)
  if not ok then
    state:close()
    vim.notify("LazyGit theme: " .. tostring(err), vim.log.levels.WARN, { title = "git-tools" })
    return
  end
  return state
end

return M
