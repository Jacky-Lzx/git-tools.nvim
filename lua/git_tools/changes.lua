local git, repository, ui = require("git_tools.git"), require("git_tools.repository"), require("git_tools.ui")
local operations = require("git_tools.operations")
local M = {}

function M.split(item, lines)
  local groups, group = {}, nil
  for _, line in ipairs(lines) do
    if not group or line:match("^diff %-%-git ") then
      group = { header = {}, hunks = {} }
      groups[#groups + 1] = group
    end
    if line:match("^@@ ") then
      group.hunks[#group.hunks + 1] = {}
    end
    local target = #group.hunks == 0 and group.header or group.hunks[#group.hunks]
    target[#target + 1] = line
  end
  local items, source_index = {}, 0
  for group_index, section in ipairs(groups) do
    for _, line in ipairs(section.header) do
      if line:match("^%+%+%+ ") then
        source_index = source_index + 1
      end
    end
    if #section.hunks == 0 then
      items[#items + 1] = vim.tbl_extend(
        "force",
        {},
        item,
        { lines = section.header, text = item.text .. " [binary/metadata]" }
      )
    else
      for index, body in ipairs(section.hunks) do
        local entry = vim.tbl_extend("force", {}, item)
        entry.sources = item.sources and { item.sources[source_index] } or nil
        entry.hunk, entry.patch_group, entry.header, entry.body = index, group_index, section.header, body
        entry.lnum = math.max(1, tonumber(body[1]:match(" %+(%d+)")) or 1)
        for n = 2, #body do
          local prefix = body[n]:sub(1, 1)
          if prefix == "+" or prefix == "-" then
            break
          end
          if prefix == " " then
            entry.lnum = entry.lnum + 1
          end
        end
        entry.pos = { entry.lnum, 0 }
        entry.lines = vim.list_extend(vim.deepcopy(section.header), body)
        entry.text = item.text .. "  " .. body[1]
        items[#items + 1] = entry
      end
    end
  end
  return items
end

function M.query(task, repo, opts, callback)
  repository.status(task, repo, function(err, files)
    if err then
      callback(err)
      return
    end
    if opts.kind then
      files = vim.tbl_filter(function(item)
        return item.kind == opts.kind
      end, files)
    end
    if opts.group then
      callback(nil, files)
      return
    end
    local items, index = {}, 0
    local function next_file()
      index = index + 1
      local file = files[index]
      if not file then
        callback(nil, items)
        return
      end
      repository.patch(task, file, function(patch_err, lines)
        if patch_err then
          callback(patch_err)
          return
        end
        require("git_tools.diff.sources").git(task, file.root, lines, function(sources)
          file.sources = sources
          if file.kind == "conflict" then
            items[#items + 1] = vim.tbl_extend("force", {}, file, { lines = lines })
          else
            vim.list_extend(items, M.split(file, lines))
          end
          next_file()
        end)
      end)
    end
    next_file()
  end)
end

function M.apply(action, items, opts, callback)
  callback = callback or git.notify
  if #items == 0 then
    callback("No selected hunks")
    return
  end
  if not items[1].hunk then
    for _, item in ipairs(items) do
      if item.hunk then
        callback("Select whole files or hunks separately")
        return
      end
    end
    return operations.files(action, items, opts, callback)
  end
  local first, groups, order = items[1], {}, {}
  local repo = { root = first.root, git_dir = first.git_dir }
  local function validate()
    for _, item in ipairs(items) do
      if not item.hunk or item.root ~= repo.root then
        return "Select hunks from the same repository"
      end
      if item.kind == "conflict" then
        return "Resolve conflicts in the merge view"
      end
      if (action == "unstage") ~= (item.kind == "staged") then
        return "Stage/Discard requires unstaged hunks; Unstage requires staged hunks"
      end
      if item.snapshot ~= repository.stamp(repo, item) then
        return "Repository or file changed; refresh and retry"
      end
      if action == "restore" then
        if item.kind == "untracked" then
          return "Discard never deletes untracked files"
        end
        if operations.modified(item.file) then
          return "Unsaved buffer: " .. item.path
        end
      end
    end
  end
  local err = validate()
  if err then
    callback(err)
    return
  end
  if action == "restore" then
    if not operations.confirm("Discard " .. #items .. " selected disk hunks?", opts) then
      callback(nil, false)
      return
    end
    err = validate()
    if err then
      callback(err)
      return
    end
  end
  if action ~= "stage" and action ~= "unstage" and action ~= "restore" then
    callback("Unknown hunk action")
    return
  end
  for _, item in ipairs(items) do
    local key = item.kind .. "\0" .. item.path .. "\0" .. item.patch_group
    if not groups[key] then
      groups[key] = { header = item.header, hunks = {} }
      order[#order + 1] = key
    end
    groups[key].hunks[item.hunk] = item.body
  end
  local patch = {}
  for _, key in ipairs(order) do
    local group = groups[key]
    vim.list_extend(patch, group.header)
    local indices = vim.tbl_keys(group.hunks)
    table.sort(indices)
    for _, index in ipairs(indices) do
      vim.list_extend(patch, group.hunks[index])
    end
  end
  local args = { "apply", "--whitespace=nowarn" }
  if action ~= "restore" then
    args[#args + 1] = "--cached"
  end
  if action ~= "stage" then
    args[#args + 1] = "--reverse"
  end
  args[#args + 1] = "-"
  local task = git.task()
  git.run(task, repo.root, args, function(failure)
    if not failure then
      operations.refresh()
    end
    callback(failure, not failure)
  end, { stdin = table.concat(patch, "\n") .. "\n" })
  return task
end

function M.jump(item)
  local buf, win = ui.open_file(item)
  if not buf or not item.hunk then
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local function position(err, text)
    if
      err
      or not vim.api.nvim_win_is_valid(win)
      or vim.api.nvim_win_get_buf(win) ~= buf
      or vim.api.nvim_buf_get_changedtick(buf) ~= tick
    then
      return
    end
    local h = require("git_tools.hunks")
    local target, delta = item.lnum, 0
    for _, change in ipairs(h.diff(h.text(text), require("git_tools.buffer").contents(buf))) do
      local first = change.old_count == 0 and change.old_start + 1 or change.old_start
      if item.lnum < first then
        break
      end
      if change.old_count > 0 and item.lnum < first + change.old_count then
        target = math.max(1, change.new_start + math.min(item.lnum - first, math.max(0, change.new_count - 1)))
        delta = 0
        break
      end
      delta = delta + change.new_count - change.old_count
    end
    vim.api.nvim_win_set_cursor(win, { math.min(vim.api.nvim_buf_line_count(buf), target + delta), 0 })
  end
  if item.kind == "staged" then
    require("git_tools.view").blob(git.task(), { root = item.root }, ":0", item.path, position)
  else
    local fd = vim.uv.fs_open(item.file, "r", 0)
    if fd then
      local size = vim.uv.fs_fstat(fd).size
      local text = size <= 4 * 1024 * 1024 and vim.uv.fs_read(fd, size, 0) or nil
      vim.uv.fs_close(fd)
      if text then
        position(nil, text)
      end
    end
  end
end

function M.open(opts)
  opts = vim.tbl_extend("force", {}, opts or {})
  local repo
  local function load(task, current, callback)
    repo = current
    M.query(task, current, opts, callback)
  end
  local controller = operations.controller(function(task, callback)
    load(task, repo, callback)
  end)
  local actions = {}
  for _, name in ipairs({ "stage", "unstage", "restore" }) do
    actions[name] = function(picker)
      local items = vim.deepcopy(picker:selected({ fallback = true }))
      if #items == 0 then
        return
      end
      controller:run(picker, function(done)
        M.apply(name, items, opts, done)
      end)
    end
  end
  actions.refresh = function(picker)
    if repo then
      controller:refresh(picker)
    end
  end
  actions.group = function(picker)
    if controller.busy then
      return
    end
    opts.group = not opts.group
    if repo then
      controller:refresh(picker)
    end
  end
  return ui.pick(
    opts,
    "Git changes · F4 files/hunks",
    load,
    ui.preview(function(task, item, callback)
      if item.lines then
        callback(nil, item.lines, item.sources)
      else
        repository.patch(task, item, callback)
      end
    end, opts),
    M.jump,
    {
      multi = true,
      components = require("git_tools.picker_components").for_kind("changes"),
      actions = actions,
      keys = {
        stage = { "<C-s>" },
        unstage = { "<C-z>" },
        restore = { "<C-r>" },
        group = { "<F4>" },
        refresh = { "<F5>" },
      },
      on_close = function()
        controller:close()
      end,
    }
  )
end
return M
