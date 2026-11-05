local M = {}
local api = vim.api
local defaults = { wrap = false }

function M.configure(opts)
  defaults.wrap = opts.wrap == true
end

function M.options(opts)
  return vim.tbl_extend("force", {}, defaults, opts or {})
end

-- Bind only while a diff owns the host. Picker state survives item replacement;
-- window options and any previous buffer mappings are restored on release.
function M.attach(ctx, opts)
  local picker = ctx.picker
  local state = {
    wrap = opts.wrap == true,
    maps = {},
    previous = api.nvim_win_is_valid(ctx.win) and vim.wo[ctx.win].wrap or false,
  }
  if picker and picker.git_tools_diff_wrap ~= nil then
    state.wrap = picker.git_tools_diff_wrap
  end
  local function toggle()
    if
      state.closed
      or not api.nvim_win_is_valid(ctx.win)
      or ctx.is_cancelled and ctx.is_cancelled()
      or state.valid and not state.valid()
    then
      return
    end
    state.wrap = not state.wrap
    if picker then
      picker.git_tools_diff_wrap = state.wrap
    end
    if state.changed then
      state.changed(state.wrap)
    end
    state:apply()
  end
  state.toggle = toggle
  local function bind(buf, mode)
    if not buf or not api.nvim_buf_is_valid(buf) then
      return
    end
    local key = buf .. mode
    if state.maps[key] then
      return
    end
    local previous = api.nvim_buf_call(buf, function()
      return vim.fn.maparg("<M-z>", mode, false, true)
    end)
    state.maps[key] = { buf = buf, mode = mode, previous = previous }
    vim.keymap.set(mode, "<M-z>", toggle, { buffer = buf, silent = true, desc = "Toggle diff wrap" })
  end
  function state:apply()
    if self.closed or not api.nvim_win_is_valid(ctx.win) then
      return
    end
    local buf = api.nvim_win_get_buf(ctx.win)
    -- Side-by-side frames wrap each column themselves.
    vim.wo[ctx.win].wrap = self.wrap and not vim.b[buf].git_tools_diff_columns
    bind(buf, "n")
    if picker then
      for _, input in ipairs({ picker.input_buf, picker.list_buf, picker.preview_buf }) do
        bind(input, "n")
        bind(input, "i")
      end
    end
  end
  function state:close()
    if self.closed then
      return
    end
    self.closed = true
    for _, map in pairs(self.maps) do
      if api.nvim_buf_is_valid(map.buf) then
        api.nvim_buf_call(map.buf, function()
          local current = vim.fn.maparg("<M-z>", map.mode, false, true)
          if current.callback == toggle then
            vim.keymap.del(map.mode, "<M-z>", { buffer = map.buf })
            if map.previous.buffer == 1 then
              vim.fn.mapset(map.mode, false, map.previous)
            end
          end
        end)
      end
    end
    if api.nvim_win_is_valid(ctx.win) then
      vim.wo[ctx.win].wrap = self.previous
    end
  end
  return state
end

return M
