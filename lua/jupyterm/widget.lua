local buf_helpers = require("jupyterm.buf_helpers")
local widget_layout = require("jupyterm.widget_layout")
local utils = require("jupyterm.utils")

local widget = {}

--- Creates the three buffers for a kernel's widget.
---@param kernel string
function widget.create(kernel)
  local kernel_name = Jupyterm.kernels[kernel].kernel_name

  local output_buf = buf_helpers.create_scratch_buf({ filetype = "jupyterm-repl-" .. kernel_name })
  utils.rename_buffer(output_buf, "jupyterm:" .. kernel_name .. ":" .. kernel)
  vim.api.nvim_set_option_value("modifiable", false, { buf = output_buf })

  local vars_buf = buf_helpers.create_scratch_buf({ filetype = "jupyterm-vars-" .. kernel_name })
  utils.rename_buffer(vars_buf, "jupyterm-vars:" .. kernel_name .. ":" .. kernel)
  vim.api.nvim_set_option_value("modifiable", false, { buf = vars_buf })

  -- Input buffer gets the real language filetype for LSP, completions, indent, etc.
  local language = Jupyterm.kernel_to_lang[kernel_name] or "python"
  local input_buf = buf_helpers.create_scratch_buf({ filetype = language })
  utils.rename_buffer(input_buf, "jupyterm-input:" .. kernel_name .. ":" .. kernel)

  Jupyterm.kernels[kernel].widget = {
    buf_nrs = {
      output = output_buf,
      variables = vars_buf,
      input = input_buf,
    },
    win_nrs = {},
  }

  for _, bufnr in ipairs({ output_buf, input_buf }) do
    vim.api.nvim_create_autocmd("BufWinLeave", {
      buffer = bufnr,
      callback = function()
        -- Ignore BufWinLeave that fires when the input popup opens/closes
        if widget._popping_input then return end
        local w2 = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
        if w2 and w2._popup_win then return end
        widget.hide(kernel)
      end,
    })
  end

  -- QuitPre closes sibling widget windows so :q/:qa can proceed normally
  vim.api.nvim_create_autocmd("QuitPre", {
    buffer = output_buf,
    callback = function()
      widget._close_siblings(kernel, "output")
    end,
  })
  vim.api.nvim_create_autocmd("QuitPre", {
    buffer = input_buf,
    callback = function()
      local w2 = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
      -- If the window being quit is the popup, close only the popup
      if w2 and w2._popup_win and vim.fn.win_getid() == w2._popup_win then
        widget.pop_input_close(kernel)
        return
      end
      widget._close_siblings(kernel, "input")
    end,
  })
end

--- Binds keymaps on the input buffer.
--- Uses a BufEnter autocmd to re-assert keymaps every time the buffer is entered,
--- ensuring they always take priority over LSP/plugin mappings.
---@param input_buf integer
---@private
function widget._bind_input_keymaps(input_buf)
  local function apply_keymaps()
    if not vim.api.nvim_buf_is_valid(input_buf) then return end
    -- Don't overwrite popup keymaps while the popup is open
    local kernel = utils.find_kernel(input_buf)
    local w = kernel and Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
    if w and w._popup_win and vim.api.nvim_win_is_valid(w._popup_win) then return end
    for _, km in ipairs(Jupyterm.config.ui.repl.input_keymaps) do
      vim.keymap.set(km[1], km[2], km[3], { desc = km[4], buffer = input_buf, nowait = true })
    end
    for _, km in ipairs(Jupyterm.config.ui.repl.global_keymaps) do
      vim.keymap.set(km[1], km[2], km[3], { desc = km[4], buffer = input_buf, nowait = true })
    end
  end

  -- Apply immediately
  apply_keymaps()

  -- Re-apply on every BufEnter to override any late-binding plugins
  vim.api.nvim_create_autocmd("BufEnter", {
    group = "Jupyterm",
    buffer = input_buf,
    callback = apply_keymaps,
  })
end

--- Shows the widget windows for a kernel.
---@param kernel string
---@param focus? boolean whether to focus the input pane (default: config.focus_on_show)
function widget.show(kernel, focus)
  if focus == nil then
    focus = Jupyterm.config.focus_on_show
  end

  local w = Jupyterm.kernels[kernel].widget
  if not w then
    widget.create(kernel)
    w = Jupyterm.kernels[kernel].widget
  end

  local cfg = {
    position = Jupyterm.config.ui.repl.position,
    width = Jupyterm.config.ui.repl.width,
    height = Jupyterm.config.ui.repl.height,
    input_height = Jupyterm.config.ui.repl.input_height,
  }
  widget_layout.open(w.buf_nrs, w.win_nrs, cfg)

  -- Set winbar titles
  local winbar_suffix = "  %#Comment#See keymaps: ?%*"
  if w.win_nrs.output and vim.api.nvim_win_is_valid(w.win_nrs.output) then
    vim.api.nvim_set_option_value(
      "winbar",
      "%#Title# Output %*" .. winbar_suffix,
      { win = w.win_nrs.output }
    )
  end
  if w.win_nrs.input and vim.api.nvim_win_is_valid(w.win_nrs.input) then
    vim.api.nvim_set_option_value(
      "winbar",
      "%#Title# Input %*" .. winbar_suffix,
      { win = w.win_nrs.input }
    )
  end

  -- Bind input keymaps (deferred to run after FileType autocmds)
  widget._bind_input_keymaps(w.buf_nrs.input)

  if focus then
    vim.schedule(function()
      if w.win_nrs.input and vim.api.nvim_win_is_valid(w.win_nrs.input) then
        vim.api.nvim_set_current_win(w.win_nrs.input)
      end
    end)
  end
end

--- Closes all widget windows except the given pane.
--- Used by QuitPre so :q/:qa can close the remaining window naturally.
---@param kernel string
---@param except string pane name to keep ("output" or "input")
---@private
function widget._close_siblings(kernel, except)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end
  -- If the popup is open, :q on the popup window should just close the popup
  if widget._popping_input then return end
  widget._closing = true
  for _, winid in pairs(w.win_nrs) do
    if winid and vim.api.nvim_win_is_valid(winid) then
      pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = winid })
    end
  end
  for name, winid in pairs(w.win_nrs) do
    if name ~= except and winid and vim.api.nvim_win_is_valid(winid) then
      w.win_nrs[name] = nil
      pcall(vim.api.nvim_win_close, winid, true)
    end
  end
  widget._closing = false
end

--- Hides all widget windows for a kernel (preserves buffers).
---@param kernel string
function widget.hide(kernel)
  if widget._closing or widget._popping_input then return end
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  local any_open = false
  for _, winid in pairs(w.win_nrs) do
    if winid and vim.api.nvim_win_is_valid(winid) then
      any_open = true
      break
    end
  end
  if not any_open then
    for name, _ in pairs(w.win_nrs) do
      w.win_nrs[name] = nil
    end
    return
  end

  -- Ensure a non-widget window exists so we don't close the last window
  local widget_wins = {}
  for _, winid in pairs(w.win_nrs) do
    if winid then widget_wins[winid] = true end
  end
  local has_fallback = false
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not widget_wins[winid] then
      has_fallback = true
      break
    end
  end
  if not has_fallback and vim.v.dying == 0 and vim.v.exiting == vim.NIL then
    vim.cmd("topleft vnew")
  end

  for name, winid in pairs(w.win_nrs) do
    w.win_nrs[name] = nil
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

--- Toggles the widget for a kernel.
---@param kernel? string
---@param focus? boolean
function widget.toggle(kernel, focus)
  kernel = utils.get_kernel(kernel)

  -- Auto start if not started
  if not Jupyterm.kernels[kernel] then
    local ft = vim.bo.filetype
    local kernel_name = Jupyterm.lang_to_kernel[ft] or Jupyterm.lang_to_kernel["python"]
    local manage_kernels = require("jupyterm.manage_kernels")
    manage_kernels.start_kernel(nil, nil, kernel_name)
  end

  if widget.is_open(kernel) then
    widget.hide(kernel)
  else
    widget.show(kernel, focus)
    -- Render output after showing
    local display = require("jupyterm.display")
    display.render_output(kernel)
  end
end

--- Destroys widget buffers and windows for a kernel.
---@param kernel string
function widget.destroy(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  widget_layout.close_all(w.win_nrs)

  for _, bufnr in pairs(w.buf_nrs) do
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end

  Jupyterm.kernels[kernel].widget = nil
end

--- Toggles the variables pane.
---@param kernel? string
function widget.toggle_variables(kernel)
  kernel = utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  if not widget.is_open(kernel) then return end

  local vars_config = Jupyterm.config.ui.repl.variables
  if w.win_nrs.variables and vim.api.nvim_win_is_valid(w.win_nrs.variables) then
    widget_layout.close_variables(w.win_nrs)
  else
    -- Trigger a fresh variables query
    local display = require("jupyterm.display")
    display.request_variables(kernel)
    -- Open the pane (content will be populated by refresh timer or inline)
    widget_layout.open_variables(w.buf_nrs, w.win_nrs, vars_config.max_height)
    if w.win_nrs.variables and vim.api.nvim_win_is_valid(w.win_nrs.variables) then
      vim.api.nvim_set_option_value(
        "winbar",
        "%#Title# Variables %*  %#Comment#" .. vars_config.command .. "%*",
        { win = w.win_nrs.variables }
      )
    end
  end
end

--- Closes the input popup if open, without hiding the main widget.
--- Called by keymaps, QuitPre, and BufWinLeave guards.
---@param kernel string
function widget.pop_input_close(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w or not w._popup_win then return end
  if not vim.api.nvim_win_is_valid(w._popup_win) then
    w._popup_win = nil
    w._popup_border_win = nil
    w._popup_border_buf = nil
    return
  end
  widget._popping_input = true
  local content_win  = w._popup_win
  local border_win   = w._popup_border_win
  local border_buf   = w._popup_border_buf
  w._popup_win        = nil
  w._popup_border_win = nil
  w._popup_border_buf = nil
  pcall(vim.api.nvim_win_close, content_win, true)
  if border_win then pcall(vim.api.nvim_win_close, border_win, true) end
  if border_buf then pcall(vim.api.nvim_buf_delete, border_buf, { force = true }) end
  widget._popping_input = false
  widget._bind_input_keymaps(w.buf_nrs.input)
  vim.schedule(function()
    if w.win_nrs.input and vim.api.nvim_win_is_valid(w.win_nrs.input) then
      vim.api.nvim_set_current_win(w.win_nrs.input)
    end
  end)
end

--- Opens the input buffer in a centered floating popup for easier editing.
---@param kernel? string
function widget.pop_input(kernel)
  kernel = utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  -- Don't open a second popup if one is already active
  if w._popup_win and vim.api.nvim_win_is_valid(w._popup_win) then
    vim.api.nvim_set_current_win(w._popup_win)
    return
  end

  local input_buf = w.buf_nrs.input
  local width  = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines   * 0.5)
  local row    = math.floor((vim.o.lines   - height) / 2) - 1
  local col    = math.floor((vim.o.columns - width)  / 2)

  -- Border window (decorative, not focusable)
  local border_buf = vim.api.nvim_create_buf(false, true)
  local top_line    = "╭" .. string.rep("─", width - 2) .. "╮"
  local mid_line    = "│" .. string.rep(" ", width - 2) .. "│"
  local bottom_line = "╰" .. string.rep("─", width - 2) .. "╯"
  local border_lines = { top_line }
  for _ = 1, height do table.insert(border_lines, mid_line) end
  table.insert(border_lines, bottom_line)
  vim.api.nvim_buf_set_lines(border_buf, 0, -1, false, border_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = border_buf })

  local border_win = vim.api.nvim_open_win(border_buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height + 2,
    style = "minimal",
    focusable = false,
    zindex = 49,
  })

  -- Content window (the real input buffer, sits inside the border)
  local content_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    row = row + 1,
    col = col + 1,
    width = width - 2,
    height = height,
    style = "minimal",
    zindex = 50,
  })

  vim.api.nvim_set_option_value("winbar",
    "%#Title# Input %*  %#Comment#<CR> run  q/<Esc> close%*",
    { win = content_win })

  w._popup_win        = content_win
  w._popup_border_win = border_win
  w._popup_border_buf = border_buf

  -- Schedule so these land after BufEnter autocmds (which would otherwise
  -- re-apply the normal input keymaps on top of ours).
  local map_opts = { buffer = input_buf, nowait = true }
  vim.schedule(function()
    if not (w._popup_win and vim.api.nvim_win_is_valid(w._popup_win)) then return end
    vim.keymap.set("n", "q",     function() widget.pop_input_close(kernel) end,
      vim.tbl_extend("force", map_opts, { desc = "Close popup" }))
    vim.keymap.set("n", "<Esc>", function() widget.pop_input_close(kernel) end,
      vim.tbl_extend("force", map_opts, { desc = "Close popup" }))
    vim.keymap.set("n", "<CR>",  function()
      widget.pop_input_close(kernel)
      require("jupyterm.execute").send_input_pane(kernel)
    end, vim.tbl_extend("force", map_opts, { desc = "Submit and close popup" }))
  end)
end

--- Returns whether the widget is currently visible.
---@param kernel string
---@return boolean
function widget.is_open(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return false end
  return w.win_nrs.output ~= nil and vim.api.nvim_win_is_valid(w.win_nrs.output)
end

return widget