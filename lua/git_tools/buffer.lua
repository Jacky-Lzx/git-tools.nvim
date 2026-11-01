local api, uv = vim.api, vim.uv
local git, h = require("git_tools.git"), require("git_tools.hunks")
local M =
  { states = {}, config = { signs = false, numhl = true, word_diff = false, line_blame = false, debounce = 100 } }
local ns = api.nvim_create_namespace("GitToolsSigns")
local overlay_ns = api.nvim_create_namespace("GitToolsOverlay")
local blame_ns = api.nvim_create_namespace("GitToolsBlame")
local group

local function valid(s)
  return M.states[s.buf] == s and api.nvim_buf_is_valid(s.buf) and api.nvim_buf_get_name(s.buf) == s.name
end

local function contents(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 1 and lines[1] == "" and not vim.bo[buf].endofline then
    lines = {}
  end
  return h.text(h.serialize(lines, vim.bo[buf].endofline, false))
end
M.contents = contents

local function highlight_words(buf, row, old, new)
  local a, b = 0, 0
  while a < math.min(#old, #new) and old:byte(a + 1) == new:byte(a + 1) do
    a = a + 1
  end
  while a > 0 and new:byte(a + 1) and new:byte(a + 1) >= 128 and new:byte(a + 1) < 192 do
    a = a - 1
  end
  while b < math.min(#old - a, #new - a) and old:byte(#old - b) == new:byte(#new - b) do
    b = b + 1
  end
  local finish = #new - b
  while finish < #new and new:byte(finish + 1) >= 128 and new:byte(finish + 1) < 192 do
    finish = finish + 1
  end
  if finish > a then
    api.nvim_buf_set_extmark(buf, ns, row, a, { end_col = finish, hl_group = "GitToolsWordAdd", priority = 150 })
  end
end

function M.draw(s)
  if not valid(s) or not s.index then
    return
  end
  local buf, count = s.buf, api.nvim_buf_line_count(s.buf)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, overlay_ns, 0, -1)
  local summary = { added = 0, changed = 0, removed = 0 }
  for _, change in ipairs(s.hunks) do
    local old, new = change.old_count, change.new_count
    summary.added = summary.added + math.max(0, new - old)
    summary.changed = summary.changed + math.min(old, new)
    summary.removed = summary.removed + math.max(0, old - new)
    local first, last = h.bounds(change)
    local kind = old == 0 and "Add" or new == 0 and "Delete" or "Change"
    for line = first, last do
      local mark = { priority = 6, strict = false }
      if M.config.signs then
        mark.sign_text = kind == "Delete" and "_" or "┃"
        mark.sign_hl_group = "GitTools" .. kind
      end
      if M.config.numhl then
        mark.number_hl_group = "GitTools" .. kind
      end
      if s.overlay and new > 0 then
        mark.line_hl_group = "GitToolsAddLine"
      end
      if M.config.signs or M.config.numhl or s.overlay then
        api.nvim_buf_set_extmark(buf, ns, math.min(count, line) - 1, 0, mark)
      end
      if M.config.word_diff and old > 0 and new > 0 and line - first < old then
        highlight_words(buf, line - 1, s.index.lines[change.old0 + line - first + 1] or "", s.text.lines[line] or "")
      end
    end
    if s.overlay and old > 0 then
      local virt_lines = {}
      for i = change.old0 + 1, change.old0 + old do
        virt_lines[#virt_lines + 1] = { { "- " .. s.index.lines[i], "GitToolsDeleteLine" } }
      end
      api.nvim_buf_set_extmark(
        buf,
        overlay_ns,
        math.min(count - 1, change.new0),
        0,
        { virt_lines = virt_lines, virt_lines_above = change.new0 < count, strict = false }
      )
    end
  end
  s.summary = summary
  vim.b[buf].git_tools_status =
    { added = summary.added, changed = summary.changed, removed = summary.removed, head = s.branch }
  api.nvim_exec_autocmds("User", { pattern = "GitToolsUpdate", data = { buf = buf }, modeline = false })
end

-- Read index mode/object explicitly so untracked and unmerged paths differ.
function M.read(task, repo, path, callback)
  git.run(task, repo.root, { "ls-files", "--stage", "-z", "--", path }, function(err, output)
    if err then
      callback(err)
      return
    end
    local mode, sha, stage = output:match("^(%d+) (%x+) (%d+)\t")
    if stage and stage ~= "0" then
      callback("Resolve merge conflicts before hunk operations")
      return
    end
    if mode and mode ~= "100644" and mode ~= "100755" then
      callback("Hunk operations require a regular text file")
      return
    end
    local function head(index)
      git.run(task, repo.root, { "ls-tree", "-z", "HEAD", "--", path }, function(head_err, tree)
        if head_err and not head_err:find("Not a valid object name HEAD", 1, true) then
          callback(head_err)
          return
        end
        local _, head_sha = tree:match("^(%d+) blob (%x+)\t")
        local function finish(head_text)
          if index:find("\0", 1, true) or head_text:find("\0", 1, true) then
            callback("Binary file; hunk operations are unavailable")
            return
          end
          callback(nil, {
            index = h.text(index),
            head = h.text(head_text),
            exists = sha ~= nil,
            head_exists = head_sha ~= nil,
            mode = mode or "100644",
          })
        end
        if head_sha then
          git.run(task, repo.root, { "cat-file", "blob", head_sha }, function(e, text)
            if e then
              callback(e)
            else
              finish(text)
            end
          end)
        else
          finish("")
        end
      end)
    end
    if sha then
      git.run(task, repo.root, { "cat-file", "blob", sha }, function(e, text)
        if e then
          callback(e)
        else
          head(text)
        end
      end)
    else
      head("")
    end
  end)
end

function M.refresh(buf, callback)
  buf = buf == 0 and api.nvim_get_current_buf() or buf
  local s = M.states[buf]
  if not s or not valid(s) then
    if callback then
      callback("Buffer is not attached")
    end
    return
  end
  s.waiters = s.waiters or {}
  if callback then
    s.waiters[#s.waiters + 1] = callback
  end
  callback = function(err, state)
    local waiters = s.waiters
    s.waiters = {}
    for _, waiter in ipairs(waiters) do
      waiter(err, state)
    end
  end
  if s.task then
    s.task:close()
  end
  local task = git.task()
  s.task = task
  local tick = api.nvim_buf_get_changedtick(buf)
  local function load(repo)
    local path, err = git.path(repo, s.name)
    if err then
      if callback then
        callback(err)
      end
      return
    end
    M.read(task, repo, path, function(read_err, data)
      if not valid(s) or task.cancelled then
        return
      end
      if read_err then
        s.error = read_err
        if callback then
          callback(read_err)
        end
        return
      end
      if tick ~= api.nvim_buf_get_changedtick(buf) then
        M.refresh(buf)
        return
      end
      s.repo, s.path, s.index, s.head = repo, path, data.index, data.head
      s.exists, s.head_exists, s.mode, s.error = data.exists, data.head_exists, data.mode, nil
      s.text, s.tick = contents(buf), tick
      s.hunks, s.staged = h.diff(s.index, s.text), h.diff(s.head, s.index)
      git.run(task, repo.root, { "symbolic-ref", "--quiet", "--short", "HEAD" }, function(_, branch)
        if valid(s) then
          s.branch = branch:gsub("\n$", "")
          if not s.attached and M.config.on_attach then
            s.attached = true
            M.config.on_attach(buf)
          end
          M.draw(s)
          if callback then
            callback(nil, s)
          end
        end
      end)
      if not s.watcher then
        s.watcher = uv.new_fs_event()
        s.watcher:start(
          repo.git_dir,
          {},
          vim.schedule_wrap(function(_, file)
            if
              valid(s) and (not file or file == "index" or file == "index.lock" or file == "HEAD" or file == "refs")
            then
              M.schedule(buf)
            end
          end)
        )
        -- Poll the index inode as well: rename-based updates and macOS event
        -- coalescing can omit the destination filename from directory events.
        s.poll = uv.new_fs_poll()
        s.poll:start(
          repo.git_dir .. "/index",
          500,
          vim.schedule_wrap(function()
            if valid(s) then
              M.schedule(buf)
            end
          end)
        )
      end
    end)
  end
  if s.repo then
    load(s.repo)
  else
    git.discover(task, { buf = buf }, function(err, repo)
      if err then
        s.error = err
        if callback then
          callback(err)
        end
      else
        load(repo)
      end
    end)
  end
end

function M.schedule(buf)
  local s = M.states[buf]
  if not s or not valid(s) then
    return
  end
  if s.timer then
    s.timer:stop()
    s.timer:close()
  end
  local timer = uv.new_timer()
  s.timer = timer
  timer:start(
    M.config.debounce,
    0,
    vim.schedule_wrap(function()
      if valid(s) and s.timer == timer then
        timer:close()
        s.timer = nil
        M.refresh(buf)
      end
    end)
  )
end

function M.attach(buf)
  buf = (not buf or buf == 0) and api.nvim_get_current_buf() or buf
  if type(buf) ~= "number" then
    buf = api.nvim_get_current_buf()
  end
  if M.states[buf] then
    return M.states[buf]
  end
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" or api.nvim_buf_get_name(buf) == "" then
    return
  end
  local s = { buf = buf, name = api.nvim_buf_get_name(buf), hunks = {}, overlay = false }
  M.states[buf] = s
  api.nvim_buf_attach(buf, false, {
    on_lines = function()
      M.schedule(buf)
    end,
    on_detach = function()
      M.detach(buf)
    end,
  })
  M.refresh(buf)
  return s
end

function M.detach(buf)
  local s = M.states[buf]
  if not s then
    return
  end
  M.states[buf] = nil
  if s.mutating then
    s.mutating:close()
  end
  local waiters = s.waiters or {}
  s.waiters = {}
  for _, waiter in ipairs(waiters) do
    waiter("Buffer detached")
  end
  if s.task then
    s.task:close()
  end
  for _, key in ipairs({ "timer", "watcher", "poll" }) do
    if s[key] and not s[key]:is_closing() then
      s[key]:stop()
      s[key]:close()
    end
  end
  if api.nvim_buf_is_valid(buf) then
    for _, namespace in ipairs({ ns, overlay_ns, blame_ns }) do
      api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    end
    vim.b[buf].git_tools_status = nil
  end
end

function M.ready(buf, callback)
  buf = (not buf or buf == 0) and api.nvim_get_current_buf() or buf
  if type(buf) ~= "number" then
    buf = api.nvim_get_current_buf()
  end
  M.attach(buf)
  M.refresh(buf, callback)
end

function M.get_hunks(buf)
  local s = M.states[(not buf or buf == 0) and api.nvim_get_current_buf() or buf]
  return s and s.hunks or {}
end

function M.toggle(name, value)
  if value == nil then
    value = not M.config[name]
  end
  M.config[name] = value
  for _, s in pairs(M.states) do
    M.draw(s)
  end
  if name == "line_blame" and not value then
    for buf in pairs(M.states) do
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_clear_namespace(buf, blame_ns, 0, -1)
      end
    end
  end
  return value
end

function M.toggle_overlay(buf)
  M.ready(buf, function(err, s)
    if err then
      git.notify(err)
    else
      s.overlay = not s.overlay
      M.draw(s)
    end
  end)
end

local function groups()
  for name, target in pairs({
    Add = "DiffAdd",
    Change = "DiffChange",
    Delete = "DiffDelete",
    AddLine = "DiffAdd",
    DeleteLine = "DiffDelete",
    WordAdd = "DiffText",
  }) do
    api.nvim_set_hl(0, "GitTools" .. name, { link = target, default = true })
  end
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  if group then
    api.nvim_del_augroup_by_id(group)
  end
  group = api.nvim_create_augroup("GitToolsBuffer", { clear = true })
  groups()
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = groups })
  api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufEnter", "BufFilePost" }, {
    group = group,
    callback = function(args)
      local s = M.states[args.buf]
      if s and s.name ~= api.nvim_buf_get_name(args.buf) then
        M.detach(args.buf)
      end
      M.attach(args.buf)
      M.schedule(args.buf)
    end,
  })
  api.nvim_create_autocmd({ "BufWritePost", "FocusGained" }, {
    group = group,
    callback = function()
      for buf in pairs(M.states) do
        M.schedule(buf)
      end
    end,
  })
  api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
    group = group,
    callback = function(args)
      api.nvim_buf_clear_namespace(args.buf, blame_ns, 0, -1)
    end,
  })
  api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function(args)
      local s = M.states[args.buf]
      if not M.config.line_blame or not s or not s.repo then
        return
      end
      local line, tick = api.nvim_win_get_cursor(0)[1], api.nvim_buf_get_changedtick(args.buf)
      require("git_tools.history").blame({ buf = args.buf }, function(err, items)
        if
          not err
          and valid(s)
          and api.nvim_get_current_buf() == args.buf
          and api.nvim_buf_get_changedtick(args.buf) == tick
          and api.nvim_win_get_cursor(0)[1] == line
          and M.config.line_blame
        then
          api.nvim_buf_clear_namespace(args.buf, blame_ns, 0, -1)
          if items[1] then
            api.nvim_buf_set_extmark(
              args.buf,
              blame_ns,
              line - 1,
              0,
              { virt_text = { { "  " .. (items[1].author or "") .. ": " .. (items[1].summary or ""), "Comment" } } }
            )
          end
        end
      end)
    end,
  })
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) then
      M.attach(buf)
    end
  end
end

return M
