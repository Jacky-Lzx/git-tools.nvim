local api = vim.api
local git, buffer, h = require("git_tools.git"), require("git_tools.buffer"), require("git_tools.hunks")
local M = {}

local function range(opts, hunks)
  if opts.all then
    return nil
  end
  if opts.range then
    return { math.min(opts.range[1], opts.range[2]), math.max(opts.range[1], opts.range[2]) }
  end
  local line = opts.line or api.nvim_win_get_cursor(0)[1]
  for _, change in ipairs(hunks) do
    local first, last = h.bounds(change)
    if line >= first and line <= last then
      return { first, last }
    end
  end
  return { -1, -1 }
end

local function complete(opts, err)
  if opts.callback then
    opts.callback(err)
  else
    git.notify(err)
  end
end

function M.change(action, opts)
  opts = vim.tbl_extend("force", { line = api.nvim_win_get_cursor(0)[1] }, opts or {})
  local buf = opts.buf or api.nvim_get_current_buf()
  if action ~= "reset" then
    local s = buffer.states[buf]
    if s and s.mutating then
      complete(opts, "A Git index operation is already running")
      return
    end
  end
  buffer.ready(buf, function(err, s)
    if err then
      complete(opts, err)
      return
    end
    if s.mutating then
      complete(opts, "A Git index operation is already running")
      return
    end
    local before, after, changes = s.index, s.text, s.hunks
    local selected = range(opts, changes)
    local reverse = action == "reset"
    if action == "unstage" then
      before, after, changes = s.head, s.index, s.staged
      if not opts.all then
        -- Map buffer positions back through unstaged changes to index lines.
        local function index_line(line)
          local delta = 0
          for _, change in ipairs(s.hunks) do
            local first, last = h.bounds(change)
            if line < first then
              break
            end
            if line <= last then
              return math.max(1, change.old_start + math.min(line - first, math.max(0, change.old_count - 1)))
            end
            delta = delta + change.old_count - change.new_count
          end
          return math.max(1, line + delta)
        end
        local requested = opts.range or { opts.line, opts.line }
        local mapped = { index_line(math.min(unpack(requested))), index_line(math.max(unpack(requested))) }
        selected = mapped
        if not opts.range then
          for _, change in ipairs(changes) do
            local first, last = h.bounds(change)
            if mapped[1] >= first and mapped[1] <= last then
              selected = { first, last }
              break
            end
          end
        end
      else
        selected = nil
      end
      reverse = true
    end
    local desired, count = h.project(before, after, changes, selected, reverse)
    if count == 0 and not (opts.all and action == "stage" and not s.exists) then
      complete(opts, "No matching hunk")
      return
    end
    if action == "reset" then
      if api.nvim_buf_get_changedtick(buf) ~= s.tick then
        complete(opts, "Buffer changed; retry the operation")
        return
      end
      -- This edits only the buffer; disk is changed by an explicit user save.
      api.nvim_buf_set_lines(buf, 0, -1, false, #desired.lines == 0 and { "" } or desired.lines)
      vim.bo[buf].endofline = desired.eol
      buffer.refresh(buf, function(refresh_err)
        complete(opts, refresh_err)
      end)
      return
    end
    local old_exists, new_exists = s.exists, true
    if action == "unstage" and not s.head_exists and desired.text == "" then
      new_exists = false
    end
    local raw_before = h.serialize(s.index.lines, s.index.eol, s.index.crlf)
    local crlf = s.index.crlf
    if not s.exists then
      crlf = vim.bo[buf].fileformat == "dos"
    end
    local raw_after = h.serialize(desired.lines, desired.eol, crlf)
    local patch = h.patch(s.path, raw_before, raw_after, old_exists, new_exists, s.mode)
    local task, snapshot, tick = git.task(), s.index.text, s.tick
    s.mutating = task
    -- Recheck both index and buffer before Git applies the context-checked patch.
    buffer.read(task, s.repo, s.path, function(read_err, data)
      if
        read_err
        or data.index.text ~= snapshot
        or data.exists ~= old_exists
        or not api.nvim_buf_is_valid(buf)
        or api.nvim_buf_get_changedtick(buf) ~= tick
      then
        s.mutating = nil
        complete(opts, read_err or "Index or buffer changed; retry the operation")
        return
      end
      git.run(task, s.repo.root, { "apply", "--cached", "--whitespace=nowarn", "-" }, function(apply_err)
        s.mutating = nil
        buffer.refresh(buf, function(refresh_err)
          complete(opts, apply_err or refresh_err)
        end)
      end, { stdin = patch })
    end)
  end)
end

function M.nav(direction, opts)
  opts = opts or {}
  if vim.wo.diff then
    vim.cmd.normal({ (direction == "prev" or direction == "first") and "[c" or "]c", bang = true })
    return
  end
  local win = api.nvim_get_current_win()
  buffer.ready(opts.buf, function(err, s)
    if err then
      git.notify(err)
      return
    end
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= s.buf then
      return
    end
    local line, target = api.nvim_win_get_cursor(win)[1], nil
    local hunks = opts.staged and s.staged or s.hunks
    if direction == "first" then
      target = hunks[1]
    elseif direction == "last" then
      target = hunks[#hunks]
    elseif direction == "next" then
      for _, change in ipairs(hunks) do
        if h.bounds(change) > line then
          target = change
          break
        end
      end
    else
      for i = #hunks, 1, -1 do
        if h.bounds(hunks[i]) < line then
          target = hunks[i]
          break
        end
      end
    end
    if target then
      api.nvim_win_set_cursor(win, { math.min(api.nvim_buf_line_count(s.buf), h.bounds(target)), 0 })
    end
  end)
end

function M.select()
  local buf, line = api.nvim_get_current_buf(), api.nvim_win_get_cursor(0)[1]
  local s = buffer.states[buf]
  if not s or not s.index or s.tick ~= api.nvim_buf_get_changedtick(buf) then
    git.notify("Hunks are refreshing; retry selection")
    return
  end
  for _, change in ipairs(s.hunks) do
    local first, last = h.bounds(change)
    if first <= line and line <= last then
      vim.cmd("normal! \27")
      api.nvim_win_set_cursor(0, { first, 0 })
      vim.cmd("normal! V")
      api.nvim_win_set_cursor(0, { math.min(last, api.nvim_buf_line_count(buf)), 0 })
      return
    end
  end
end

function M.preview(opts)
  opts = opts or {}
  buffer.ready(opts.buf, function(err, s)
    if err then
      git.notify(err)
      return
    end
    local selected = range(opts, s.hunks)
    local projected, count = h.project(s.index, s.text, s.hunks, selected, false)
    if count == 0 then
      git.notify("No matching hunk")
      return
    end
    local lines = require("git_tools.diff").unified(s.index.text, projected.text, { old_path = s.path })
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "diff"
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    api.nvim_open_win(buf, true, {
      relative = "cursor",
      row = 1,
      col = 0,
      width = math.max(1, math.min(100, vim.o.columns - 4)),
      height = math.max(1, math.min(#lines, math.floor(vim.o.lines * 0.6))),
      style = "minimal",
      border = "rounded",
    })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
    vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf })
  end)
end

function M.quickfix(opts)
  opts = opts or {}
  if not opts.all then
    buffer.ready(opts.buf, function(err, s)
      if err then
        git.notify(err)
        return
      end
      local entries = {}
      for _, change in ipairs(s.hunks) do
        entries[#entries + 1] = {
          filename = s.name,
          lnum = h.bounds(change),
          text = string.format("+%d -%d", change.new_count, change.old_count),
        }
      end
      vim.fn.setqflist({}, " ", { title = "Git buffer hunks", items = entries })
      vim.cmd("copen")
    end)
    return
  end
  local task = git.task()
  git.discover(task, opts, function(err, repo)
    if err then
      git.notify(err)
      return
    end
    local repository = require("git_tools.repository")
    repository.status(task, repo, function(status_err, items)
      if status_err then
        git.notify(status_err)
        return
      end
      local entries, i = {}, 0
      local function next_item()
        i = i + 1
        if not items[i] then
          vim.fn.setqflist({}, " ", { title = "Git repository hunks (disk/index)", items = entries })
          vim.cmd("copen")
          return
        end
        local item = items[i]
        repository.patch(task, item, function(patch_err, lines)
          if patch_err then
            git.notify(patch_err)
            return
          end
          for _, line in ipairs(lines) do
            local row = line:match("^@@ .- %+(%d+)")
            if row then
              entries[#entries + 1] =
                { filename = item.file, lnum = math.max(1, tonumber(row)), text = item.kind .. " " .. line }
            end
          end
          next_item()
        end)
      end
      next_item()
    end)
  end)
  return task
end

return M
