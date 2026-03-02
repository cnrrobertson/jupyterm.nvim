---@tag Jupyterm.execute
---@signature Jupyterm.execute
local utils = require("jupyterm.utils")
local display = require("jupyterm.display")
local manage_kernels = require("jupyterm.manage_kernels")

local execute = {}

--- Sends code to a Jupyter kernel and updates the REPL buffer.
---@param kernel string The kernel to send the code to.
---@param code string The code to send.
function execute.send(kernel, code)
  vim.fn.JupyEval(tostring(kernel), code)

  -- Update window
  local widget = require("jupyterm.widget")
  if widget.is_open(tostring(kernel)) or Jupyterm.config.show_on_send then
    if not widget.is_open(tostring(kernel)) then
      widget.show(tostring(kernel), Jupyterm.config.focus_on_send)
      display.render_output(tostring(kernel))
    end
    display.scroll_output_to_bottom(tostring(kernel))
  end

  -- Auto-update variables if enabled and variables pane is showing
  local vars_config = Jupyterm.config.ui.repl.variables
  if vars_config.auto_update then
    local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
    if w and w.win_nrs.variables and vim.api.nvim_win_is_valid(w.win_nrs.variables) then
      -- Delay to let execution complete before querying variables
      vim.defer_fn(function()
        if Jupyterm.kernels[kernel] then
          display.request_variables(kernel)
        end
      end, 500)
    end
  end
end

--- Sends current output block of code to a Jupyter kernel (re-execute from output pane).
---@private
function execute.send_display_block()
  local kernel = utils.get_kernel_if_in_widget_buf()
  if not kernel then return end

  local w = Jupyterm.kernels[kernel].widget
  if not w then return end

  local bufnr = w.buf_nrs.output
  local winid = w.win_nrs.output
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local top_in = utils.get_extmark_above_buf(bufnr, cursor[1], Jupyterm.ns_in_top)
  local bottom_in = utils.get_extmark_below_buf(bufnr, cursor[1], Jupyterm.ns_in_bottom)
  local top_out = utils.get_extmark_above_buf(bufnr, cursor[1], Jupyterm.ns_out_top)
  local bottom_out = utils.get_extmark_below_buf(bufnr, cursor[1], Jupyterm.ns_out_bottom)

  if top_in then top_in = top_in[2] + 1 end
  if bottom_in then bottom_in = bottom_in[2] + 1 end
  if bottom_out then bottom_out = bottom_out[2] + 1 end
  if top_out then top_out = top_out[2] + 1 end

  -- Ensure we don't send Out results
  if top_in and top_out and top_out > top_in then
    return
  end

  -- Find bottom of input block
  local bottom = 0
  if bottom_in then
    if bottom_out and bottom_in > bottom_out then
      bottom = bottom_out - 1
    else
      bottom = bottom_in - 1
    end
  else
    bottom = vim.api.nvim_buf_line_count(bufnr)
  end

  -- Clean up lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, top_in, bottom, false)
  local clean_lines = {}
  for _, l in ipairs(lines) do
    if utils.strip(l) ~= "" then
      table.insert(clean_lines, l .. "\n")
    end
  end

  if #clean_lines == 0 then return end

  vim.fn.JupyEval(tostring(kernel), unpack(clean_lines))
  display.render_output(kernel)
end

--- Sends code from the input pane to the kernel.
---@param kernel? string
function execute.send_input_pane(kernel)
  -- Find kernel from widget buffer if not specified
  if not kernel then
    kernel = utils.find_kernel(vim.api.nvim_get_current_buf())
  end
  kernel = kernel or utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  local input_buf = w.buf_nrs.input
  local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)

  -- Clean and join lines
  local clean_lines = {}
  local whitespace = 0
  for i, v in ipairs(lines) do
    if string.gsub(v, "%s+", "") ~= "" then
      if i == 1 then
        local leading_whitespace = string.match(v, "^%s+")
        if leading_whitespace then
          whitespace = leading_whitespace:len()
        end
      end
      clean_lines[#clean_lines + 1] = string.sub(v, whitespace + 1)
    end
  end

  if #clean_lines == 0 then return end

  clean_lines[#clean_lines + 1] = ""
  local combined = table.concat(clean_lines, "\n")

  -- Clear input buffer and reset history position
  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, {})
  Jupyterm.kernels[kernel].history_idx = nil

  -- Send code
  execute.send(kernel, combined)
end

--- Saves or retrieves the kernel location for sending code.
---@param kernel string?
---@return string kernel
---@private
function execute.save_kernel_location(kernel)
  if kernel then
    return kernel
  else
    local buf = vim.api.nvim_get_current_buf()
    if Jupyterm.send_memory[buf] then
      return Jupyterm.send_memory[buf]
    else
      return execute.select_send_term()
    end
  end
end

--- Selects a kernel to send code to.
---@return string new_kernel
---@private
function execute.select_send_term()
  local buf = vim.api.nvim_get_current_buf()
  local kernel = manage_kernels.select_kernel()
  if Jupyterm.kernels[kernel] == nil then
    manage_kernels.start_kernel(kernel)
  end
  local memory = Jupyterm.send_memory[buf]
  if memory and (memory ~= kernel) then
    display.hide_all_virt_text(memory)
    Jupyterm.kernels[memory].virt_buf = nil
  end
  Jupyterm.send_memory[buf] = kernel
  return kernel
end

--- Sends code to a selected kernel.
---@param kernel string?
---@param cmd string
function execute.send_select(kernel, cmd)
  kernel = kernel or execute.select_send_term()
  execute.send(kernel, cmd)
end

--- Sends the current line to a Jupyter kernel.
---@param kernel string?
function execute.send_line(kernel)
  kernel = execute.save_kernel_location(kernel)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, true)
  line = string.gsub(line[1], "^%s+", "")
  execute.send_select(kernel, line)

  -- Store virtual text information
  local output_length = vim.fn.JupyOutputLen(tostring(kernel))
  Jupyterm.kernels[kernel].virt_buf = vim.api.nvim_get_current_buf()
  Jupyterm.kernels[kernel].virt_text[output_length] = {
    start_row = row - 1,
    end_row = row - 1,
    start_col = nil,
    end_col = nil,
    hl = nil
  }
  if Jupyterm.config.inline_display and Jupyterm.kernels[kernel].show_virt then
    display.show_virt_text(kernel, nil, row - 1, row - 1)
  end
end

--- Sends multiple lines of code to a Jupyter kernel.
---@param kernel string?
---@param start_line integer
---@param end_line integer
function execute.send_lines(kernel, start_line, end_line)
  kernel = execute.save_kernel_location(kernel)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local no_empty = {}
  local whitespace = 0
  for i, v in ipairs(lines) do
    if (string.gsub(v, "%s+", "") ~= "") then
      if i == 1 then
        local leading_whitespace = string.match(v, "^%s+")
        if leading_whitespace then
          whitespace = leading_whitespace:len()
        end
      end
      no_empty[#no_empty + 1] = string.sub(v, whitespace + 1)
    end
  end
  no_empty[#no_empty + 1] = ""
  local combined = table.concat(no_empty, "\n")
  execute.send_select(kernel, combined)

  -- Store virtual text information
  local output_length = vim.fn.JupyOutputLen(tostring(kernel))
  Jupyterm.kernels[kernel].virt_buf = vim.api.nvim_get_current_buf()
  Jupyterm.kernels[kernel].virt_text[output_length] = {
    start_row = start_line - 1,
    end_row = end_line - 1,
    start_col = nil,
    end_col = nil,
    hl = nil
  }
  if Jupyterm.config.inline_display and Jupyterm.kernels[kernel].show_virt then
    display.show_virt_text(kernel, nil, start_line - 1, end_line - 1)
  end
end

--- Sends a selection of code to a Jupyter kernel.
---@param kernel string
---@param line integer
---@param start_col integer
---@param end_col integer
---@private
function execute.send_selection(kernel, line, start_col, end_col)
  local sc = nil
  local ec = nil
  if start_col > end_col then
    sc = end_col
    ec = start_col
  else
    sc = start_col
    ec = end_col
  end
  local text = vim.api.nvim_buf_get_text(0, line - 1, sc - 1, line - 1, ec, {})
  execute.send_select(kernel, table.concat(text))

  -- Store virtual text information
  local output_length = vim.fn.JupyOutputLen(tostring(kernel))
  Jupyterm.kernels[kernel].virt_buf = vim.api.nvim_get_current_buf()
  Jupyterm.kernels[kernel].virt_text[output_length] = {
    start_row = line - 1,
    end_row = line - 1,
    start_col = start_col - 1,
    end_col = end_col,
    hl = "CursorLine"
  }
  if Jupyterm.config.inline_display and Jupyterm.kernels[kernel].show_virt then
    display.show_virt_text(kernel, output_length, line - 1, line - 1, start_col - 1, end_col, "CursorLine")
  end
end

--- Sends the visually selected code to a Jupyter kernel.
---@param kernel string?
function execute.send_visual(kernel)
  kernel = execute.save_kernel_location(kernel)
  local start_line, start_col = unpack(vim.fn.getpos("v"), 2, 4)
  local end_line, end_col = unpack(vim.fn.getpos("."), 2, 4)
  if (start_line == end_line) and (start_col ~= end_col) then
    execute.send_selection(kernel, start_line, start_col, end_col)
  else
    if start_line > end_line then
      execute.send_lines(kernel, end_line, start_line)
    else
      execute.send_lines(kernel, start_line, end_line)
    end
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
end

--- Sends the entire file to a Jupyter kernel.
---@param kernel string?
function execute.send_file(kernel)
  kernel = execute.save_kernel_location(kernel)
  local start_line = 1
  local end_line = vim.api.nvim_buf_line_count(0)
  execute.send_lines(kernel, start_line, end_line)
end

return execute