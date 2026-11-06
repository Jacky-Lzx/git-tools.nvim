-- Own the floating terminal, session theme and job; LazyGit owns the Git interface.
local api = vim.api
local M = {}
local defaults = { command = "lazygit", args = {}, width = 0.9, height = 0.9, border = "rounded", theme = true }
local initial = vim.deepcopy(defaults)

local function dimension(value, available)
  assert(
    type(value) == "number" and value > 0 and (value <= 1 or value % 1 == 0),
    "Terminal size must be a positive fraction or integer"
  )
  return math.max(1, math.min(available, math.floor(value <= 1 and available * value or value)))
end

local function geometry(opts)
  local columns, rows = math.max(1, vim.o.columns - 2), math.max(1, vim.o.lines - 4)
  local width, height = dimension(opts.width, columns), dimension(opts.height, rows)
  return {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((columns - width) / 2),
    row = math.floor((rows - height) / 2),
  }
end

local function refresh()
  -- checktime respects modified buffers; it never force-reloads unsaved text.
  pcall(vim.cmd, "checktime")
  local buffers = package.loaded["git_tools.buffer"]
  if buffers then
    for buf in pairs(buffers.states) do
      buffers.schedule(buf)
    end
  end
end

function M.resolve(opts)
  assert(opts == nil or type(opts) == "table", "lazygit options must be a table")
  local candidate = vim.tbl_extend("force", vim.deepcopy(initial), vim.deepcopy(opts or {}))
  assert(type(candidate.command) == "string", "LazyGit command must be a string")
  assert(type(candidate.args) == "table" and vim.islist(candidate.args), "LazyGit args must be a list")
  for _, arg in ipairs(candidate.args) do
    assert(type(arg) == "string", "LazyGit arguments must be strings")
  end
  dimension(candidate.width, 100)
  dimension(candidate.height, 100)
  return candidate
end

function M.configure(opts)
  defaults = M.resolve(opts)
end

function M.dispose()
  if M.current then
    local session = M.current
    local keep = api.nvim_buf_is_valid(session.buf)
      and vim.bo[session.buf].buftype ~= "terminal"
      and vim.bo[session.buf].modified
    session:close(false, keep)
  end
  defaults = vim.deepcopy(initial)
end

function M.open(opts)
  if M.current and not M.current.closed then
    local session = M.current
    if api.nvim_win_is_valid(session.win) then
      api.nvim_set_current_win(session.win)
      if not session.exited then
        vim.cmd.startinsert()
      end
      return session
    end
    session:close()
  end
  opts = vim.tbl_extend("force", {}, defaults, opts or {})
  assert(type(opts.command) == "string", "LazyGit command must be an executable name or path")
  assert(type(opts.args) == "table" and vim.islist(opts.args), "LazyGit args must be a list")
  for _, arg in ipairs(opts.args) do
    assert(type(arg) == "string", "LazyGit arguments must be strings")
  end
  local function failure(message)
    require("git_tools.git").notify(message)
    return nil, message
  end
  if vim.fn.executable(opts.command) ~= 1 then
    return failure("Executable not found: " .. opts.command)
  end
  local cwd = opts.cwd
  if not cwd then
    local path = api.nvim_buf_get_name(0)
    cwd = vim.bo.buftype == "" and path ~= "" and vim.fs.dirname(path) or vim.fn.getcwd()
  end
  cwd = vim.fn.fnamemodify(cwd, ":p")
  if vim.fn.isdirectory(cwd) ~= 1 then
    return failure("Terminal directory does not exist: " .. cwd)
  end
  local config = vim.tbl_extend(
    "force",
    geometry(opts),
    { relative = "editor", style = "minimal", border = opts.border, title = " Lazygit ", title_pos = "center" }
  )
  local session = { buf = api.nvim_create_buf(false, true), origin = api.nvim_get_current_win(), cwd = cwd }
  function session:resize()
    if not self.closed and api.nvim_win_is_valid(self.win) then
      api.nvim_win_set_config(self.win, geometry(opts))
      if self.job and not self.exited then
        pcall(vim.fn.jobresize, self.job, api.nvim_win_get_width(self.win), api.nvim_win_get_height(self.win))
      end
    end
  end
  function session:close(update, keep_buffer)
    if self.closed then
      return
    end
    self.closed = true
    if M.current == self then
      M.current = nil
    end
    local focused = self.win and api.nvim_get_current_win() == self.win
    if self.group then
      api.nvim_del_augroup_by_id(self.group)
    end
    if self.job and not self.exited then
      pcall(vim.fn.jobstop, self.job)
    end
    if self.theme then
      self.theme:close()
    end
    if self.win and api.nvim_win_is_valid(self.win) then
      pcall(api.nvim_win_close, self.win, not keep_buffer)
    end
    if not keep_buffer and api.nvim_buf_is_valid(self.buf) then
      pcall(api.nvim_buf_delete, self.buf, { force = true })
    end
    if focused and api.nvim_win_is_valid(self.origin) then
      api.nvim_set_current_win(self.origin)
    end
    if focused then
      vim.cmd.stopinsert()
    end
    if update ~= false then
      vim.schedule(refresh)
    end
  end
  vim.bo[session.buf].bufhidden = "wipe"
  vim.bo[session.buf].swapfile = false
  local opened, win = pcall(api.nvim_open_win, session.buf, true, config)
  if not opened then
    session:close(false)
    return failure(tostring(win))
  end
  session.win = win
  M.current = session
  for name, value in pairs({
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    winbar = "",
    statuscolumn = "",
    colorcolumn = "",
    spell = false,
  }) do
    vim.wo[win][name] = value
  end
  session.group = api.nvim_create_augroup("GitToolsLazygit" .. session.buf, { clear = true })
  api.nvim_create_autocmd("VimResized", {
    group = session.group,
    callback = function()
      session:resize()
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = session.group,
    pattern = tostring(win),
    callback = function()
      session:close()
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = session.group,
    buffer = session.buf,
    callback = function()
      session:close()
    end,
  })
  api.nvim_create_autocmd("VimLeavePre", {
    group = session.group,
    callback = function()
      session:close(false)
    end,
  })
  vim.keymap.set({ "n", "t" }, "<C-g>", function()
    session:close()
  end, { buffer = session.buf, silent = true, desc = "Close Lazygit" })
  vim.keymap.set("n", "q", function()
    session:close()
  end, { buffer = session.buf, silent = true, desc = "Close Lazygit" })
  session.theme = require("git_tools.lazygit_theme").prepare(vim.tbl_extend("force", {}, opts, { cwd = cwd }))
  local argv = vim.list_extend({ opts.command }, session.theme and session.theme.args or opts.args)
  local started, job = pcall(vim.fn.termopen, argv, {
    cwd = cwd,
    env = session.theme and session.theme.env or opts.env,
    on_exit = function(_, code)
      vim.schedule(function()
        if session.closed then
          return
        end
        session.exited = true
        if code == 0 then
          session:close()
        else
          if api.nvim_get_current_win() == session.win then
            vim.cmd.stopinsert()
          end
          require("git_tools.git").notify(
            "Lazygit exited with code " .. code .. "; terminal output retained (q closes)"
          )
        end
      end)
    end,
  })
  if not started or job <= 0 then
    session:close(false)
    return failure("Unable to start Lazygit: " .. tostring(job))
  end
  session.job = job
  if session.theme then
    session.theme:attach(session)
  end
  vim.bo[session.buf].filetype = "git-tools-lazygit"
  vim.cmd.startinsert()
  return session
end

return M
