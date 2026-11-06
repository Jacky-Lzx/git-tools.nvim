local git = require("git_tools.git")
local M = {}

function M.scratch(lines, title, filetype)
  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "git-tools://" .. buf .. "/" .. title)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype or "diff"
  vim.bo[buf].modifiable = false
  vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = buf, silent = true, desc = "Close Git output" })
  return buf
end

function M.open_file(item)
  if vim.fn.filereadable(item.file) == 1 or vim.fn.bufnr(item.file) ~= -1 then
    vim.cmd.edit(vim.fn.fnameescape(item.file))
    vim.api.nvim_win_set_cursor(0, { math.min(item.lnum or 1, vim.api.nvim_buf_line_count(0)), 0 })
    return vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  else
    git.notify("File is absent from the working tree: " .. item.path)
  end
end

function M.preview(loader, opts)
  return function(ctx)
    local task, renderer = git.task(), nil
    loader(task, ctx.item, function(err, lines, sources)
      if task.cancelled or ctx.is_cancelled() then
        return
      end
      if err then
        ctx.set_lines({ err }, "text", "Git error")
        return
      end
      if #lines == 0 then
        lines = { "No text changes." }
      end
      local function publish(snapshots)
        if task.cancelled or ctx.is_cancelled() then
          return
        end
        renderer = require("git_tools.diff").render(
          ctx,
          lines,
          vim.tbl_extend("force", {}, opts or {}, { cwd = ctx.item.root, sources = snapshots })
        )
      end
      if sources then
        publish(sources)
      else
        require("git_tools.diff.sources").git(task, ctx.item.root, lines, publish)
      end
    end)
    return {
      close = function()
        task:close()
        if renderer then
          renderer:close()
        end
      end,
      resize = function()
        if renderer then
          renderer:resize()
        end
      end,
    }
  end
end

function M.pick(opts, title, loader, preview, on_choice, extra)
  opts = vim.tbl_extend("force", {}, opts or {})
  -- Capture the source before the picker makes its input buffer current.
  if not opts.cwd then
    local buf = opts.buf or 0
    local name = vim.api.nvim_buf_get_name(buf)
    opts.cwd = vim.bo[buf].buftype == "" and name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
  end
  local ok, selection = pcall(require, "selection_tools")
  if not ok then
    git.notify("Install selection-tools.nvim to use Git pickers")
    return
  end
  local config = vim.tbl_extend("force", {
    prompt = title,
    resume = false,
    cwd = opts.cwd,
    finder = function(ctx)
      local task = git.task()
      git.discover(task, opts, function(err, repo)
        if err then
          ctx.fail(err)
          return
        end
        loader(task, repo, function(load_err, items)
          if load_err then
            ctx.fail(load_err)
            return
          end
          ctx.set_items(items)
          ctx.done()
        end)
      end)
      return function()
        task:close()
      end
    end,
    format_item = function(item)
      return item.text
    end,
    preview = { enabled = true, providers = { preview } },
    on_choice = function(item)
      if item then
        (on_choice or M.open_file)(item)
      end
    end,
  }, extra or {}, opts.picker or {})
  return selection.open(config)
end

return M
