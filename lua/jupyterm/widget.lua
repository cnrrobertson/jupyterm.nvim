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
    for _, k in ipairs(Jupyterm.config.ui.repl.input_keymaps) do
      vim.keymap.set(k[1], k[2], k[3], { desc = k[4], buffer = input_buf, nowait = true })
    end
    for _, k in ipairs(Jupyterm.config.ui.repl.global_keymaps) do
      vim.keymap.set(k[1], k[2], k[3], { desc = k[4], buffer = input_buf, nowait = true })
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
  if widget._closing then return end
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

--- Opens the input buffer in a centered floating popup for easier editing.
---@param kernel? string
function widget.pop_input(kernel)
  kernel = utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  local Popup = require("nui.popup")
  local input_buf = w.buf_nrs.input

  local popup = Popup({
    bufnr = input_buf,
    enter = true,
    focusable = true,
    relative = "editor",
    position = "50%",
    size = {
      width = "60%",
      height = "50%",
    },
    border = {
      style = "rounded",
      text = {
        top = " Input ",
        top_align = "center",
        bottom = " Run: cr | Close: q/esc ",
        bottom_align = "center",
      },
    },
  })

  popup:mount()

  local function close()
    popup:unmount()
  end

  local function submit()
    popup:unmount()
    local execute = require("jupyterm.execute")
    execute.send_input_pane(kernel)
  end

  popup:map("n", "q", close)
  popup:map("n", "<Esc>", close)
  popup:map("n", "<CR>", submit)
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