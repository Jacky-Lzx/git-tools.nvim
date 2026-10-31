local M = {}

-- Render already-computed unified diffs. Edit semantics stay with the caller.
function M.render(ctx, lines, opts, valid)
  opts = opts or {}
  local delta = vim.tbl_extend("force", { command = "delta", args = {}, timeout = 2000 }, opts.delta or {})
  local cancelled, process, generation = false, nil, 0
  local function current()
    return not cancelled and not ctx.is_cancelled() and (not valid or valid())
  end
  local function plain()
    if current() then
      ctx.set_lines(lines, "diff", opts.title or "Preview")
    end
  end
  local function stop()
    if process and not process:is_closing() then
      process:kill(15)
    end
    process = nil
  end
  local function draw()
    stop()
    if not current() then
      return
    end
    local text = table.concat(lines, "\n")
    if opts.backend ~= "delta" or not text:find("\n@@ ", 1, true) or vim.fn.executable(delta.command) ~= 1 then
      plain()
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
    generation = generation + 1
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
          plain()
          return
        end
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].bufhidden = "hide"
        if not ctx.set_buffer(buf, { owned = true, title = "Preview · delta" }) then
          return
        end
        local rendered = pcall(function()
          local channel = vim.api.nvim_open_term(buf, {})
          vim.api.nvim_chan_send(channel, output.stdout)
        end)
        if not rendered then
          plain()
        end
      end)
    end)
    if ok then
      process = result
    else
      plain()
    end
  end
  local handle = {}
  function handle:close()
    cancelled = true
    stop()
  end
  function handle:resize()
    draw()
  end
  draw()
  return handle
end

return M
