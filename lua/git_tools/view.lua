local api = vim.api
local scratch_buffer = require("base_tools.buffer").scratch
local keymaps = require("base_tools.keymap")
local git, repository = require("git_tools.git"), require("git_tools.repository")
local compare = require("git_tools.compare_config")
local tree = require("git_tools.view_tree")
local M = { active = {} }
local View = {}
View.__index = View
local panel_ns = api.nvim_create_namespace("git_tools.view.panel")
local panel_rows_ns = api.nvim_create_namespace("git_tools.view.panel.rows")

local panel_badges = { staged = "S", unstaged = "W", untracked = "?", conflict = "!" }
local panel_badge_colors = {
  S = "GitToolsCompareAdd",
  W = "GitToolsCompareChange",
  ["?"] = "GitToolsCompareAdd",
  ["!"] = "GitToolsCompareConflict",
  A = "GitToolsCompareAdd",
  D = "GitToolsCompareDelete",
  U = "GitToolsCompareConflict",
}

local function panel_badge(item)
  return panel_badges[item.kind] or item.status or "M"
end

local function bar(text)
  return text:gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end

local panel_key_labels = { ["<CR>"] = "Enter", ["<Tab>"] = "Tab" }
local function panel_key_hint(lhs, label)
  return (panel_key_labels[lhs] or vim.fn.strtrans(lhs)) .. ": " .. vim.fn.strtrans(label)
end

function View:resize()
  if not self.tab or not api.nvim_tabpage_is_valid(self.tab) or not self.windows then
    return
  end
  local total = api.nvim_win_get_width(self.panel_win)
  for _, win in ipairs(self.windows) do
    if not api.nvim_win_is_valid(win) then
      return
    end
    total = total + api.nvim_win_get_width(win) + 1
  end
  local panel = math.min(32, math.max(18, math.floor(total * 0.18)))
  api.nvim_win_set_width(self.panel_win, panel)
  local width = math.floor((total - panel - #self.windows) / #self.windows)
  for _, win in ipairs(self.windows) do
    api.nvim_win_set_width(win, math.max(1, width))
  end
end

function View:ensure_pane_order()
  local anchor, reordered = self.panel_win, false
  for _, win in ipairs(self.windows) do
    if api.nvim_win_get_position(win)[2] <= api.nvim_win_get_position(anchor)[2] then
      api.nvim_win_set_config(win, { win = anchor, split = "right" })
      reordered = true
    end
    anchor = win
  end
  if reordered then
    self:resize()
  end
end

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
  local buf = scratch_buffer({ bufhidden = "wipe" })
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
  self:unmap(buf, lhs)
  self.maps[buf][lhs] = keymaps.install("n", lhs, callback, { buffer = buf, silent = true, desc = desc })
end
function View:unmap(buf, lhs)
  local cleanup = self.maps[buf][lhs]
  if cleanup then
    self.maps[buf][lhs] = nil
    cleanup()
  end
end
function View:next_file()
  if self.panel_items ~= self.items then
    return
  end
  local rows = self.panel_rows
  local current = self.panel_file_rows[self.selection_index] or api.nvim_win_get_cursor(self.panel_win)[1]
  for offset = 1, #rows do
    local node = rows[(current + offset - 1) % #rows + 1]
    if node.index and node.index ~= self.selection_index then
      return self:select(node.index, true)
    end
  end
end
function View:map_pane_tab()
  local win = api.nvim_get_current_win()
  if self.tab_map_buf or not vim.tbl_contains(self.windows or {}, win) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  self:map(buf, "<Tab>", function()
    self:next_file()
  end, "Show next changed file")
  self.tab_map_buf = buf
end
function View:unmap_pane_tab()
  if self.tab_map_buf then
    self:unmap(self.tab_map_buf, "<Tab>")
    self.tab_map_buf = nil
  end
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
  self:unmap_pane_tab()
  for buf, maps in pairs(self.maps) do
    for lhs in pairs(maps) do
      self:unmap(buf, lhs)
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
  return true
end
function View:decorate_panel()
  if not self:alive() or not api.nvim_buf_is_loaded(self.panel) then
    return
  end
  local icons = package.loaded["theme_tools.icons"]
  local get_icon = type(icons) == "table" and icons.get
  api.nvim_buf_clear_namespace(self.panel, panel_rows_ns, 0, -1)
  for index, node in ipairs(self.panel_rows or {}) do
    local row = index - 1
    api.nvim_buf_set_extmark(self.panel, panel_rows_ns, row, node.highlight_start, {
      end_col = node.highlight_end,
      hl_group = node.highlight,
    })
    if type(get_icon) == "function" then
      local icon, hl = get_icon(node.children and "directory" or "file", node.path)
      if icon and icon ~= "" then
        api.nvim_buf_set_extmark(self.panel, panel_rows_ns, row, node.icon_col, {
          virt_text = { { icon .. " ", hl } },
          virt_text_pos = "inline",
          hl_mode = "combine",
        })
      end
    end
  end
end

function View:highlight_panel_selection()
  api.nvim_buf_clear_namespace(self.panel, panel_ns, 0, -1)
  local row = self.panel_file_rows[self.current_index]
  if row and self.panel_items[self.current_index] == self.current then
    api.nvim_buf_set_extmark(self.panel, panel_ns, row - 1, 0, { line_hl_group = "GitToolsCompareSelected" })
    return row
  end
end

function View:render_panel()
  self.panel_rows, self.panel_file_rows = tree.rows(self.tree, self.collapsed)
  local lines = {}
  for row, node in ipairs(self.panel_rows) do
    local indent = string.rep("  ", node.depth)
    local name = vim.fn.strtrans(node.name)
    if node.children then
      local marker = self.collapsed[node.path] and "▸ " or "▾ "
      lines[row] = indent .. marker .. name
      node.icon_col = #indent + #marker
      node.highlight_start, node.highlight_end = #indent, #lines[row]
      node.highlight = "GitToolsCompareDirectory"
    else
      local badge = panel_badge(self.items[node.index])
      lines[row] = indent .. " " .. badge .. "  " .. name
      node.highlight_start, node.highlight_end = #indent + 1, #indent + 1 + #badge
      node.highlight = panel_badge_colors[badge:sub(1, 1)] or "GitToolsCompareChange"
      node.icon_col = node.highlight_end + 2
    end
  end
  if #lines == 0 then
    local hints = {}
    for _, binding in ipairs(self.panel_keymap) do
      if binding.primary == "refresh" or binding.primary == "close" then
        hints[#hints + 1] = panel_key_hint(binding.lhs, binding.hint)
      end
    end
    lines = { "No changed files." .. (#hints > 0 and " " .. table.concat(hints, "; ") or "") }
  end
  vim.bo[self.panel].modifiable = true
  api.nvim_buf_set_lines(self.panel, 0, -1, false, lines)
  vim.bo[self.panel].modifiable = false
  self.panel_items = self.items
  self:highlight_panel_selection()
  self:decorate_panel()
  vim.wo[self.panel_win].winbar = " Files (" .. #self.items .. ")"
end

function View:panel_row()
  if self.panel_items == self.items then
    local row = api.nvim_win_get_cursor(self.panel_win)[1]
    return self.panel_rows[row], row
  end
end

function View:open_panel_row()
  local node, row = self:panel_row()
  if not node then
    return
  end
  if node.children then
    self.collapsed[node.path] = not self.collapsed[node.path] or nil
    self:render_panel()
    api.nvim_win_set_cursor(self.panel_win, { row, 0 })
    return true
  end
  return self:select(node.index)
end

local function change_snapshot(item)
  if item then
    return {
      path = item.path,
      old_path = item.old_path,
      file = item.file,
      kind = item.kind,
      status = item.status,
    }
  end
end

function View:run_panel_action(action)
  local spec = compare.actions[action]
  assert(spec, "Unknown Git compare panel action: " .. tostring(action))
  if not self:alive() or not api.nvim_win_is_valid(self.panel_win) then
    return false
  end
  return self[spec.method](self) == true
end

function View:panel_context()
  local node = self:panel_row()
  local row
  if node then
    row = { path = node.path, kind = node.children and "directory" or "file" }
    if node.children then
      row.collapsed = self.collapsed[node.path] == true
    else
      row.item = change_snapshot(self.items[node.index])
    end
  end

  return {
    root = self.repo.root,
    tab = self.tab,
    win = self.panel_win,
    buf = self.panel,
    row = row,
    current = change_snapshot(self.current),
    run = function(action)
      return self:run_panel_action(action)
    end,
  }
end

function View:run_panel_binding(binding)
  for _, action in ipairs(binding.actions) do
    if not self:alive() or not api.nvim_win_is_valid(self.panel_win) then
      return
    end
    local handled
    if type(action) == "function" then
      handled = action(self:panel_context())
    else
      handled = self:run_panel_action(action)
    end
    if handled == true then
      return
    end
  end
end

function View:layout(merge)
  if not self.tab then
    vim.cmd("tabnew")
    self.tab, self.panel = api.nvim_get_current_tabpage(), api.nvim_get_current_buf()
    self.panel_win = api.nvim_get_current_win()

    vim.bo[self.panel].buftype = "nofile"
    vim.bo[self.panel].buflisted = false
    vim.bo[self.panel].bufhidden = "wipe"
    vim.bo[self.panel].swapfile = false
    api.nvim_buf_set_name(self.panel, "git-tools://" .. self.panel .. "/files")
    vim.wo[self.panel_win].winfixwidth = true

    local panel_opts = {
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      statuscolumn = "",
      wrap = false,
      list = false,
      spell = false,
      cursorline = true,
      winbar = " Files",
    }
    for name, value in pairs(panel_opts) do
      vim.wo[self.panel_win][name] = value
    end

    require("git_tools.diff.theme").compare_panel(self.panel_win)

    self.group = api.nvim_create_augroup("GitToolsView" .. self.panel, { clear = true })
    api.nvim_create_autocmd("User", {
      group = self.group,
      pattern = { "ThemeToolsReady", "ThemeToolsIconsChanged" },
      callback = function()
        self:decorate_panel()
      end,
    })

    api.nvim_create_autocmd("VimResized", {
      group = self.group,
      callback = function()
        if self:alive() then
          self:resize()
        end
      end,
    })

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

    -- Working-tree buffers can also be used outside the comparison tab.
    api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
      group = self.group,
      callback = function()
        self:map_pane_tab()
      end,
    })

    api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
      group = self.group,
      callback = function()
        self:unmap_pane_tab()
      end,
    })

    local hints = {}
    for _, binding in ipairs(self.panel_keymap) do
      self:map(self.panel, binding.lhs, function()
        self:run_panel_binding(binding)
      end, binding.desc)
      hints[#hints + 1] = panel_key_hint(binding.lhs, binding.hint)
    end
    vim.wo[self.panel_win].statusline = #hints > 0 and " " .. bar(table.concat(hints, "  ")) or ""
  end

  if self.merge ~= merge or not self.windows then
    for _, win in ipairs(self.windows or {}) do
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, false)
      end
    end

    self.windows, self.merge = {}, merge

    -- Buffer and window autocmds may change focus as the panes open.
    local anchor = self.panel_win
    for index = 1, merge and 3 or 2 do
      local buf = scratch_buffer({ bufhidden = "wipe" })
      local win = api.nvim_open_win(buf, false, { win = anchor, split = "right" })
      self.windows[index] = win
      vim.wo[win].winfixwidth = false
      anchor = win
    end

    self:resize()
  end

  if self.panel_items ~= self.items then
    self:render_panel()
  end
end

function View:select(index, keep_focus)
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
  self.selection_index = index
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
  local working_tree_left = self.opts.from and not after
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
      local focused = api.nvim_get_current_win()
      self:layout(merge)
      local original = scratch(old, merge and "ours" or tostring(before), item.path)
      local result
      if not after or merge then
        if merge or vim.fn.filereadable(item.file) == 1 or vim.fn.bufnr(item.file) ~= -1 then
          result = vim.fn.bufadd(item.file)
          vim.fn.bufload(result)
        else
          result = scratch("", "deleted", item.path)
        end
      else
        result = scratch(new, tostring(after), item.path)
      end
      local buffers = merge and { original, result, scratch(new, "theirs", item.path) } or { original, result }
      local function label(revision)
        if revision == ":0" then
          return "Index"
        end
        return revision and revision:sub(1, 10) or "Empty"
      end
      local labels = merge and { "Ours", "Result · editable", "Theirs" }
        or {
          self.opts.from or (item.kind == "staged" and "HEAD" or label(before)),
          self.opts.to or (after and label(after) or "Working tree · editable"),
        }
      if working_tree_left then
        buffers[1], buffers[2] = buffers[2], buffers[1]
        labels[1], labels[2] = labels[2], labels[1]
      end
      for i, win in ipairs(self.windows) do
        require("git_tools.diff.theme").window(win)
        api.nvim_win_call(win, function()
          vim.cmd("diffoff")
        end)
        api.nvim_win_set_buf(win, buffers[i])
        api.nvim_win_call(win, function()
          vim.cmd("diffthis")
        end)
        vim.wo[win].wrap = self.wrap
        vim.wo[win].number = true
        vim.wo[win].relativenumber = false
        -- Native diff underlines changed text when CursorLine covers the text area.
        vim.wo[win].cursorlineopt = "number"
        vim.wo[win].statuscolumn = ""
        vim.wo[win].signcolumn = "no"
        vim.wo[win].foldcolumn = "1"
        vim.wo[win].winbar = "%#GitToolsDiffHunk# " .. bar(labels[i]) .. "%*  %<" .. bar(item.path)
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
      self.current, self.result, self.current_index = item, result, index
      local row = self:highlight_panel_selection()
      if row then
        api.nvim_win_set_cursor(self.panel_win, { row, 0 })
      end
      if merge then
        local conflict = require("git_tools.conflict")
        for key, kind in pairs({ co = "ours", ct = "theirs", cb = "both" }) do
          self:map(result, key, function()
            conflict.choose(kind, result)
          end, "Choose " .. kind .. " conflict changes")
        end
        self:map(result, "]x", function()
          conflict.nav("next")
        end, "Next conflict")
        self:map(result, "[x", function()
          conflict.nav("prev")
        end, "Previous conflict")
        self:map(result, "S", function()
          self:resolve()
        end, "Save and stage resolved file")
        self:map(result, "<leader>gb", function()
          M.blob(self.task, self.repo, ":1", item.path, function(base_err, text)
            if base_err then
              git.notify(base_err)
            else
              require("git_tools.ui").scratch(git.lines(text), "base/" .. item.path, vim.bo[result].filetype)
            end
          end)
        end, "Show conflict base version")
      end
      if keep_focus and api.nvim_win_is_valid(focused) then
        api.nvim_set_current_win(focused)
      else
        api.nvim_set_current_win(self.windows[working_tree_left and 1 or 2])
      end
      -- Window setup and focus callbacks have run. Verify the resulting columns.
      self:ensure_pane_order()
      self:map_pane_tab()
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
  return true
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
    self.selection_index = nil
    self.tree = tree.build(self.items)
    local rows = tree.rows(self.tree, self.collapsed)
    for _, node in ipairs(rows) do
      if node.index then
        self:select(node.index)
        return
      end
    end
    self:layout(#self.items > 0 and self.merge or false)
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
    return true
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
  return true
end

function M.open(opts)
  opts = require("git_tools.diff.window").options(opts)
  local view = setmetatable({
    opts = opts,
    panel_keymap = vim.deepcopy(compare.panel_keymap),
    wrap = opts.wrap,
    task = git.task(),
    maps = {},
    items = {},
    collapsed = {},
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
