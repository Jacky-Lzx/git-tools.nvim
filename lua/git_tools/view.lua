local api = vim.api
local git, repository = require("git_tools.git"), require("git_tools.repository")
local M = { active = {} }
local View = {}
View.__index = View

function M.parse_names(output, root)
  local fields, items, i = vim.split(output, "\0", { plain = true }), {}, 1
  while i < #fields do
    local status, path = fields[i], fields[i + 1]
    local old_path
    if status:match("^[RC]") then
      old_path, path = path, fields[i + 2]
      i = i + 1
    end
    items[#items + 1] = {
      kind = "revision",
      status = status,
      path = path,
      old_path = old_path,
      root = root,
      file = root .. "/" .. path,
      text = status .. " " .. path,
    }
    i = i + 2
  end
  return items
end

function M.blob(task, repo, revision, path, callback)
  if not revision then
    callback(nil, "")
    return
  end
  local args
  if revision:sub(1, 1) == ":" then
    args = { "ls-files", "--stage", "-z", "--", path }
  else
    args = { "ls-tree", "-z", revision, "--", path }
  end
  git.run(task, repo.root, args, function(err, output)
    if err then
      callback(err)
      return
    end
    local sha
    if revision:sub(1, 1) == ":" then
      local wanted = revision:match("^:(%d)") or "0"
      for _, record in ipairs(vim.split(output, "\0", { plain = true })) do
        local _, object, stage = record:match("^(%d+) (%x+) (%d+)\t")
        if stage == wanted then
          sha = object
          break
        end
      end
    else
      sha = output:match("^%d+ blob (%x+)\t")
    end
    if not sha then
      callback(nil, "")
      return
    end
    git.run(task, repo.root, { "cat-file", "blob", sha }, callback)
  end)
end

local function scratch(text, name, path)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  api.nvim_buf_set_name(buf, "git-tools://" .. buf .. "/" .. name .. "/" .. path)
  local parsed = require("git_tools.hunks").text(text)
  if text:find("\0", 1, true) then
    parsed.lines = { "Binary content: use the Git patch preview or an external viewer." }
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, parsed.lines)
  vim.bo[buf].filetype = vim.filetype.match({ filename = path }) or ""
  vim.bo[buf].endofline = parsed.eol
  vim.bo[buf].modifiable = false
  return buf
end

function View:alive()
  return not self.closed and (not self.tab or api.nvim_tabpage_is_valid(self.tab))
end
function View:map(buf, lhs, callback, desc)
  self.maps[buf] = self.maps[buf] or {}
  if self.maps[buf][lhs] == nil then
    self.maps[buf][lhs] =
      { previous = api.nvim_buf_call(buf, function()
        return vim.fn.maparg(lhs, "n", false, true)
      end) }
  end
  vim.keymap.set("n", lhs, callback, { buffer = buf, silent = true, desc = desc })
  self.maps[buf][lhs].installed = api.nvim_buf_call(buf, function()
    return vim.fn.maparg(lhs, "n", false, true)
  end)
end
function View:cleanup()
  if self.closed then
    return
  end
  self.closed = true
  self.task:close()
  if self.list_task then
    self.list_task:close()
  end
  if self.selection_task then
    self.selection_task:close()
  end
  for buf, maps in pairs(self.maps) do
    if api.nvim_buf_is_valid(buf) then
      for lhs, record in pairs(maps) do
        api.nvim_buf_call(buf, function()
          local current = vim.fn.maparg(lhs, "n", false, true)
          if vim.deep_equal(current, record.installed) then
            vim.keymap.del("n", lhs, { buffer = buf })
            if next(record.previous) and record.previous.buffer == 1 then
              vim.fn.mapset("n", false, record.previous)
            end
          end
        end)
      end
    end
  end
  if self.group then
    api.nvim_del_augroup_by_id(self.group)
  end
  M.active[self] = nil
end
function View:close()
  if self.tab and api.nvim_tabpage_is_valid(self.tab) then
    local previous = api.nvim_get_current_tabpage()
    api.nvim_set_current_tabpage(self.tab)
    local ok, err = pcall(vim.cmd, "tabclose")
    if not ok then
      git.notify(err)
      return
    end
    if api.nvim_tabpage_is_valid(previous) and previous ~= self.tab then
      api.nvim_set_current_tabpage(previous)
    end
  end
  self:cleanup()
end
function View:layout(merge)
  if not self.tab then
    vim.cmd("tabnew")
    self.tab, self.panel = api.nvim_get_current_tabpage(), api.nvim_get_current_buf()
    self.panel_win = api.nvim_get_current_win()
    vim.bo[self.panel].buftype = "nofile"
    vim.bo[self.panel].bufhidden = "wipe"
    vim.bo[self.panel].swapfile = false
    api.nvim_buf_set_name(self.panel, "git-tools://" .. self.panel .. "/files")
    vim.wo[self.panel_win].winfixwidth = true
    self.group = api.nvim_create_augroup("GitToolsView" .. self.panel, { clear = true })
    api.nvim_create_autocmd("TabClosed", {
      group = self.group,
      callback = function()
        vim.schedule(function()
          if not api.nvim_tabpage_is_valid(self.tab) then
            self:cleanup()
          end
        end)
      end,
    })
    self:map(self.panel, "q", function()
      self:close()
    end, "Close Git diff view")
    self:map(self.panel, "<CR>", function()
      self:select(api.nvim_win_get_cursor(self.panel_win)[1])
    end, "Show selected file diff")
    self:map(self.panel, "R", function()
      self:refresh()
    end, "Refresh Git diff view")
  end
  if self.merge ~= merge or not self.windows then
    for _, win in ipairs(self.windows or {}) do
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, false)
      end
    end
    self.windows, self.merge = {}, merge
    api.nvim_set_current_win(self.panel_win)
    vim.cmd("rightbelow vnew")
    self.windows[1] = api.nvim_get_current_win()
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.buflisted = false
    vim.cmd("rightbelow vnew")
    self.windows[2] = api.nvim_get_current_win()
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.buflisted = false
    if merge then
      vim.cmd("rightbelow vnew")
      self.windows[3] = api.nvim_get_current_win()
      vim.bo.buftype = "nofile"
      vim.bo.bufhidden = "wipe"
      vim.bo.buflisted = false
    end
    api.nvim_win_set_width(self.panel_win, math.min(35, math.max(15, math.floor(vim.o.columns * 0.2))))
  end
  local lines = {}
  for _, item in ipairs(self.items) do
    lines[#lines + 1] = item.text
  end
  if #lines == 0 then
    lines = { "No changed files. R: refresh; q: close" }
  end
  vim.bo[self.panel].modifiable = true
  api.nvim_buf_set_lines(self.panel, 0, -1, false, lines)
  vim.bo[self.panel].modifiable = false
end
function View:select(index)
  if not self:alive() then
    return
  end
  local item = self.items[index]
  if not item then
    return
  end
  if self.selection_task then
    self.selection_task:close()
  end
  local task = git.task()
  self.selection_task = task
  local merge, before, after = item.kind == "conflict", self.from, self.to
  if not self.opts.from and not self.opts.commit then
    if item.kind == "staged" then
      before, after = self.head, ":0"
    else
      before, after = ":0", nil
    end
  end
  if merge then
    before, after = ":2", ":3"
  end
  M.blob(task, self.repo, before, item.old_path or item.path, function(err, old)
    if err then
      git.notify(err)
      return
    end
    local function publish(new)
      if task.cancelled or not self:alive() then
        return
      end
      if api.nvim_get_current_tabpage() ~= (self.tab or self.origin_tab) then
        return
      end
      self:layout(merge)
      local left = scratch(old, merge and "ours" or tostring(before), item.path)
      local right
      if not after or merge then
        if merge or vim.fn.filereadable(item.file) == 1 or vim.fn.bufnr(item.file) ~= -1 then
          right = vim.fn.bufadd(item.file)
          vim.fn.bufload(right)
        else
          right = scratch("", "deleted", item.path)
        end
      else
        right = scratch(new, tostring(after), item.path)
      end
      local buffers = merge and { left, right, scratch(new, "theirs", item.path) } or { left, right }
      for i, win in ipairs(self.windows) do
        api.nvim_win_call(win, function()
          vim.cmd("diffoff")
        end)
        api.nvim_win_set_buf(win, buffers[i])
        api.nvim_win_call(win, function()
          vim.cmd("diffthis")
        end)
        vim.wo[win].wrap = self.wrap
        self:map(buffers[i], "<M-z>", function()
          self.wrap = not self.wrap
          for _, pane in ipairs(self.windows) do
            if api.nvim_win_is_valid(pane) then
              vim.wo[pane].wrap = self.wrap
            end
          end
        end, "Toggle diff wrapping")
        self:map(buffers[i], "q", function()
          self:close()
        end, "Close Git diff view")
        self:map(buffers[i], "<leader>gp", function()
          api.nvim_set_current_win(self.panel_win)
        end, "Focus Git file list")
      end
      self.current, self.result = item, right
      if merge then
        local conflict = require("git_tools.conflict")
        for key, kind in pairs({ co = "ours", ct = "theirs", cb = "both" }) do
          self:map(right, key, function()
            conflict.choose(kind, right)
          end, "Choose " .. kind .. " conflict changes")
        end
        self:map(right, "]x", function()
          conflict.nav("next")
        end, "Next conflict")
        self:map(right, "[x", function()
          conflict.nav("prev")
        end, "Previous conflict")
        self:map(right, "S", function()
          self:resolve()
        end, "Save and stage resolved file")
        self:map(right, "<leader>gb", function()
          M.blob(self.task, self.repo, ":1", item.path, function(base_err, text)
            if base_err then
              git.notify(base_err)
            else
              require("git_tools.ui").scratch(git.lines(text), "base/" .. item.path, vim.bo[right].filetype)
            end
          end)
        end, "Show conflict base version")
      end
      api.nvim_set_current_win(self.windows[2])
      if self.opts.on_ready then
        self.opts.on_ready(self)
      end
    end
    if after then
      M.blob(task, self.repo, after, item.path, function(e, text)
        if e then
          git.notify(e)
        else
          publish(text)
        end
      end)
    else
      publish("")
    end
  end)
end
function View:resolve(callback)
  if not self.current or self.current.kind ~= "conflict" then
    return
  end
  local buf, item = self.result, self.current
  if require("git_tools.conflict").has_markers(api.nvim_buf_get_lines(buf, 0, -1, false)) then
    (callback or git.notify)("Conflict markers remain in the result")
    return
  end
  local ok, err = pcall(api.nvim_buf_call, buf, function()
    vim.cmd("write")
  end)
  if not ok then
    (callback or git.notify)(err)
    return
  end
  if require("git_tools.conflict").has_markers(api.nvim_buf_get_lines(buf, 0, -1, false)) then
    (callback or git.notify)("Save hook introduced conflict markers")
    return
  end
  git.run(self.task, self.repo.root, { "add", "--", item.path }, function(add_err)
    if callback then
      callback(add_err)
    elseif add_err then
      git.notify(add_err)
    else
      vim.notify("Saved and staged resolution: " .. item.path)
    end
    if not add_err and self:alive() then
      self:refresh()
    end
  end)
end
function View:refresh()
  if not self:alive() then
    return
  end
  if self.list_task then
    self.list_task:close()
  end
  if self.selection_task then
    self.selection_task:close()
  end
  local task = git.task()
  self.list_task = task
  local function loaded(err, items)
    if err then
      git.notify(err)
      return
    end
    if task.cancelled or not self:alive() then
      return
    end
    self.items = items
    if not self.to and not self.opts.staged and not self.opts.merge then
      local seen = {}
      for _, item in ipairs(items) do
        if item.kind ~= "staged" then
          seen[item.path] = true
        end
      end
      for _, buf in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and vim.bo[buf].modified then
          local name = api.nvim_buf_get_name(buf)
          local path = name ~= "" and git.path(self.repo, name) or nil
          if path and not seen[path] then
            self.items[#self.items + 1] = { kind = "unstaged", path = path, file = name, text = "buffer    B " .. path }
            seen[path] = true
          end
        end
      end
    end
    if self.opts.include_unchanged and self.opts.path and #items == 0 then
      self.items = {
        {
          kind = "unstaged",
          path = self.opts.path,
          file = self.repo.root .. "/" .. self.opts.path,
          text = self.opts.path,
        },
      }
    end
    if self.opts.path then
      self.items = vim.tbl_filter(function(item)
        return item.path == self.opts.path
      end, items)
    end
    if #self.items > 0 then
      self:select(1)
    else
      self:layout(false)
    end
  end
  if not self.opts.from and not self.opts.commit then
    repository.status(task, self.repo, function(err, items)
      if err then
        loaded(err)
        return
      end
      if self.opts.staged then
        items = vim.tbl_filter(function(item)
          return item.kind == "staged"
        end, items)
      end
      if self.opts.merge then
        items = vim.tbl_filter(function(item)
          return item.kind == "conflict"
        end, items)
      end
      loaded(nil, items)
    end)
    return
  end
  local args
  if self.opts.commit and not self.from then
    args = { "diff-tree", "--root", "--no-commit-id", "-r", "--name-status", "-z", self.to }
  else
    args = { "diff", "--name-status", "-z", "--find-renames", self.from }
    if self.to then
      args[#args + 1] = self.to
    end
  end
  args[#args + 1] = "--"
  if self.opts.path then
    args[#args + 1] = self.opts.path
  end
  git.run(task, self.repo.root, args, function(err, output)
    loaded(err, not err and M.parse_names(output, self.repo.root) or nil)
  end)
end
function M.open(opts)
  opts = require("git_tools.diff.window").options(opts)
  local view = setmetatable({
    opts = opts,
    wrap = opts.wrap,
    task = git.task(),
    maps = {},
    items = {},
    origin_tab = api.nvim_get_current_tabpage(),
  }, View)
  M.active[view] = true
  git.discover(view.task, opts, function(err, repo)
    if err then
      git.notify(err)
      view:cleanup()
      return
    end
    view.repo = repo
    local history = require("git_tools.history")
    if opts.path and opts.path:sub(1, 1) == "/" then
      local relative, path_err = git.path(repo, opts.path)
      if path_err then
        git.notify(path_err)
        view:cleanup()
        return
      end
      opts.path = relative
    end
    if opts.commit then
      history.resolve(view.task, repo, opts.commit, function(commit_err, sha)
        if commit_err then
          git.notify(commit_err)
          view:cleanup()
          return
        end
        view.to = sha
        git.run(view.task, repo.root, { "rev-list", "--parents", "-n", "1", sha }, function(parent_err, output)
          if parent_err then
            git.notify(parent_err)
            view:cleanup()
            return
          end
          view.from = output:match("^%x+ (%x+)")
          view:refresh()
        end)
      end)
    elseif opts.from then
      history.resolve(view.task, repo, opts.from, function(from_err, sha)
        if from_err then
          git.notify(from_err)
          view:cleanup()
          return
        end
        view.from = sha
        if opts.to then
          history.resolve(view.task, repo, opts.to, function(to_err, to)
            if to_err then
              git.notify(to_err)
              view:cleanup()
            else
              view.to = to
              view:refresh()
            end
          end)
        else
          view:refresh()
        end
      end)
    else
      history.resolve(view.task, repo, "HEAD", function(_, sha)
        view.head = sha
        view:refresh()
      end)
    end
  end)
  return view
end
function M.toggle(opts)
  for view in pairs(M.active) do
    if view.tab == api.nvim_get_current_tabpage() then
      view:close()
      return
    end
  end
  return M.open(opts)
end
function M.dispose()
  for _, view in ipairs(vim.tbl_keys(M.active)) do
    view:close()
    if not view.closed then
      view:cleanup()
    end
  end
end

return M
