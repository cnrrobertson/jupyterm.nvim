local utils = require("jupyterm.utils")
local display = require("jupyterm.display")
local manage_kernels = require("jupyterm.manage_kernels")

local execute = {}

function execute.send(kernel, code)
  vim.fn.JupyEval(tostring(kernel), code)

  -- Update window
  if display.is_showing(tostring(kernel)) or Jupyterm.config.show_on_send then
    local focus = Jupyterm.config.focus_on_send
    display.show_outputs(tostring(kernel), focus)
    display.scroll_output_to_bottom(tostring(kernel))
  end

  -- Reset edited status
  Jupyterm.edited[kernel] = nil
end

function execute.send_display_block(kernel)
  if kernel == nil then
    kernel = utils.get_kernel_if_in_kernel_buf()
  end
  local cursor = vim.api.nvim_win_get_cursor(Jupyterm.kernels[kernel].show_win.winid)
  local top_in = display.get_display_block_top(cursor[1], Jupyterm.ns_in)
  local bottom_in = display.get_display_block_bottom(cursor[1], Jupyterm.ns_in)
  local bottom_out = display.get_display_block_bottom(cursor[1], Jupyterm.ns_out)
  local top_out = display.get_display_block_top(cursor[1], Jupyterm.ns_out)
  if top_in then top_in = top_in[2]+1 end
  if bottom_in then bottom_in = bottom_in[2]+1 end
  if bottom_out then bottom_out = bottom_out[2]+1 end
  if top_out then top_out = top_out[2]+1 end

  -- Ensure we don't send Out results
  local bottom = 0
  if top_in and top_out and top_out > top_in then
    return
  end

  -- Check if the last display block
  if bottom_in then
    -- Check if display block has an output
    if bottom_out and bottom_in > bottom_out then
      bottom = bottom_out-1
    else
      bottom = bottom_in-1
    end
  else
    bottom = vim.api.nvim_buf_line_count(Jupyterm.kernels[kernel].show_buf)
  end

  -- Clean up lines
  local lines = vim.api.nvim_buf_get_lines(Jupyterm.kernels[kernel].show_buf, top_in, bottom, false)
  local clean_lines = {}
  for _,l in ipairs(lines) do
    if utils.strip(l) ~= "" then
      table.insert(clean_lines, l.."\n")
    end
  end

  -- Check if empty display block
  if #clean_lines == 0 then
    return
  end

  -- Send lines
  vim.fn.JupyEval(tostring(kernel), unpack(clean_lines))

  -- Refresh
  display.show_outputs(kernel)
end

function execute.save_kernel_location(kernel)
  if kernel == nil then
    local buf = vim.api.nvim_get_current_buf()
    if Jupyterm.send_memory[buf] then
      return Jupyterm.send_memory[buf]
    else
      return execute.select_send_term()
    end
  else
    return kernel
  end
end

function execute.select_send_term()
  local buf = vim.api.nvim_get_current_buf()
  local new_kernel = manage_kernels.select_kernel()
  Jupyterm.send_memory[buf] = new_kernel
  return new_kernel
end

function execute.send_select(kernel, cmd)
  if kernel == nil then
    kernel = execute.select_send_term()
  else
    execute.send(kernel, cmd)
  end
end

function execute.send_line(kernel)
  kernel = execute.save_kernel_location(kernel)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(0,row-1,row,true)
  line = string.gsub(line[1], "^%s+", "")
  execute.send_select(kernel, line)
end

function execute.send_lines(kernel,start_line,end_line)
  kernel = execute.save_kernel_location(kernel)
  local lines = vim.api.nvim_buf_get_lines(0,start_line-1,end_line,false)
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
      no_empty[#no_empty+1] = string.sub(v, whitespace+1)
    end
  end
  no_empty[#no_empty+1] = ""
  local combined = table.concat(no_empty,"\n")
  execute.send_select(kernel,combined)
end

function execute.send_selection(kernel,line,start_col,end_col)
  local sc = nil
  local ec = nil
  if start_col > end_col then
    sc = end_col
    ec = start_col
  else
    sc = start_col
    ec = end_col
  end
  local text = vim.api.nvim_buf_get_text(0,line-1,sc-1,line-1,ec,{})
  execute.send_select(kernel,table.concat(text))
end

function execute.send_visual(kernel)
  kernel = execute.save_kernel_location(kernel)
  local start_line, start_col = unpack(vim.fn.getpos("v"), 2, 4)
  local end_line, end_col = unpack(vim.fn.getpos("."), 2, 4)
  if (start_line == end_line) and (start_col ~= end_col) then
    execute.send_selection(kernel,start_line,start_col,end_col)
  else
    if start_line > end_line then
      execute.send_lines(kernel,end_line,start_line)
    else
      execute.send_lines(kernel,start_line,end_line)
    end
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
end

function execute.send_file(kernel)
  kernel = execute.save_kernel_location(kernel)
  local start_line = 1
  local end_line = vim.api.nvim_buf_line_count(0)
  execute.send_lines(kernel,start_line,end_line)
end

return execute
