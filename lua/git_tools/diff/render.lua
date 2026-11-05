local M = {}

-- Render already-computed unified diffs. Edit semantics stay with the caller.
function M.render(ctx, lines, opts, valid)
  local window = require("git_tools.diff.window")
  opts = window.options(opts)
  local display = window.attach(ctx, opts)
  local delta = vim.tbl_extend("force", { command = "delta", args = {}, timeout = 2000 }, opts.delta or {})
  local cancelled, process, generation, pending = false, nil, 0, nil
  local native_buf
  local has_hunks = false
  for _, line in ipairs(lines) do
    if line:match("^@@ %-%d+[, ]") then
      has_hunks = true
      break
    end
  end
  local function current()
    return not cancelled and not ctx.is_cancelled() and (not valid or valid())
  end
  display.valid = current
  local function plain()
    if current() then
      ctx.set_lines(lines, "diff", opts.title or "Preview")
      display:apply()
      vim.schedule(function()
        if current() then
          display:apply()
        end
      end)
    end
  end
  local function native()
    if not current() then
      return
    end
    if not ctx.set_buffer or not has_hunks then
      plain()
      return
    end
    local buf
    local ok, adopted = pcall(function()
      local renderer = require("git_tools.diff.native")
      local width = vim.api.nvim_win_get_width(ctx.win)
      if native_buf and vim.api.nvim_buf_is_valid(native_buf) then
        renderer.resize(native_buf, width)
        return true
      end
      local truncated
      buf, truncated = renderer.prepare(
        lines,
        vim.tbl_extend("force", {}, opts.native or {}, { wrap = display.wrap }),
        width,
        opts.sources
      )
      if not current() then
        return false
      end
      return ctx.set_buffer(
        buf,
        { owned = true, backend = "native", title = opts.title or "Preview · diff", truncated = truncated }
      )
    end)
    if ok and adopted then
      native_buf = buf or native_buf
      display:apply()
    else
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
      plain()
    end
  end
  local function release(frame, adopted)
    if frame.closed then
      return
    end
    frame.closed = true
    if frame.timer and not frame.timer:is_closing() then
      frame.timer:stop()
      frame.timer:close()
    end
    if frame.win and vim.api.nvim_win_is_valid(frame.win) then
      vim.api.nvim_win_close(frame.win, true)
    end
    if not adopted and vim.api.nvim_buf_is_valid(frame.buf) then
      vim.api.nvim_buf_delete(frame.buf, { force = true })
    end
    if pending == frame then
      pending = nil
    end
  end
  local function stop()
    if process and not process:is_closing() then
      process:kill(15)
    end
    process = nil
    if pending then
      release(pending)
    end
  end
  local function draw()
    generation = generation + 1
    stop()
    if not current() then
      return
    end
    local text = table.concat(lines, "\n")
    if opts.backend == "vim" then
      plain()
      return
    end
    if opts.backend ~= "delta" or not has_hunks or vim.fn.executable(delta.command) ~= 1 then
      native()
      return
    end
    local cmd = {
      delta.command,
      "--paging=never",
      "--true-color=always",
      "--width=" .. vim.api.nvim_win_get_width(ctx.win),
    }
    if not vim.tbl_contains(delta.args, "--dark") and not vim.tbl_contains(delta.args, "--light") then
      cmd[#cmd + 1] = "--" .. vim.o.background
    end
    vim.list_extend(cmd, delta.args)
    local current_generation = generation
    local ok, result = pcall(vim.system, cmd, {
      stdin = text .. "\n",
      text = true,
      timeout = delta.timeout,
      cwd = opts.cwd,
      env = { PAGER = "cat", DELTA_PAGER = "cat" },
    }, function(output)
      vim.schedule(function()
        if not current() or generation ~= current_generation then
          return
        end
        if output.code ~= 0 or not output.stdout or output.stdout == "" then
          native()
          return
        end
        local frame = { buf = vim.api.nvim_create_buf(false, true) }
        pending = frame
        vim.bo[frame.buf].bufhidden = "hide"
        local function valid_frame()
          return not frame.closed and current() and generation == current_generation
        end
        local function publish()
          if frame.closed then
            return
          end
          if not valid_frame() then
            release(frame)
            return
          end
          -- Terminal output is flushed asynchronously. Keep the previous
          -- host frame until the prepared buffer actually contains text.
          if not table.concat(vim.api.nvim_buf_get_lines(frame.buf, 0, -1, false)):find("%S") then
            return
          end
          local ok, adopted =
            pcall(ctx.set_buffer, frame.buf, { owned = true, backend = "delta", title = "Preview · delta" })
          release(frame, ok and adopted)
          if ok and adopted then
            display:apply()
          else
            native()
          end
        end
        local rendered = pcall(function()
          -- A hidden window gives the terminal the host's exact dimensions
          -- without exposing an empty buffer or changing the host's focus.
          frame.win = vim.api.nvim_open_win(frame.buf, false, {
            relative = "editor",
            row = 0,
            col = 0,
            width = vim.api.nvim_win_get_width(ctx.win),
            height = vim.api.nvim_win_get_height(ctx.win),
            hide = true,
            focusable = false,
            style = "minimal",
            noautocmd = true,
          })
          local channel = vim.api.nvim_open_term(frame.buf, {})
          assert(channel > 0, "Cannot open preview terminal")
          vim.api.nvim_buf_attach(frame.buf, false, {
            on_lines = function()
              if frame.closed then
                return true
              end
              if not frame.queued then
                frame.queued = true
                vim.schedule(function()
                  frame.queued = false
                  publish()
                end)
              end
            end,
          })
          frame.timer = vim.defer_fn(function()
            if not frame.closed then
              release(frame)
              if current() and generation == current_generation then
                native()
              end
            end
          end, delta.timeout)
          vim.api.nvim_chan_send(channel, output.stdout)
        end)
        if not rendered then
          release(frame)
          native()
        end
      end)
    end)
    if ok then
      process = result
    else
      native()
    end
  end
  local handle = {}
  display.changed = function(wrap)
    if native_buf and vim.api.nvim_buf_is_valid(native_buf) then
      require("git_tools.diff.native").set_wrap(native_buf, wrap, vim.api.nvim_win_get_width(ctx.win))
    end
  end
  function handle:close()
    cancelled = true
    stop()
    display:close()
  end
  function handle:resize()
    draw()
  end
  function handle:toggle_wrap()
    display:toggle()
    return display.wrap
  end
  draw()
  return handle
end

return M
