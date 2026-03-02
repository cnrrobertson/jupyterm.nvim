---@tag Jupyterm.display
---@signature Jupyterm.display
local Line = require("nui.line")
local Text = require("nui.text")
local Popup = require("nui.popup")

local utils = require("jupyterm.utils")
local buf_helpers = require("jupyterm.buf_helpers")

local display = {}

--- Refreshes all output windows.
function display.refresh_windows()
  for k, _ in pairs(Jupyterm.kernels) do
    local w = Jupyterm.kernels[k].widget
    if w and w.win_nrs.output and vim.api.nvim_win_is_valid(w.win_nrs.output) then
      display.update_output(k)
    end
    -- Also refresh variables if visible
    if w and w.win_nrs.variables and vim.api.nvim_win_is_valid(w.win_nrs.variables) then
      display.update_variables_display(k)
    end
  end
end

--- Refreshes all virtual text.
function display.refresh_virt_text()
  for k, _ in pairs(Jupyterm.kernels) do
    if utils.is_virt_text_showing(k) then
      display.update_all_virt_text(k)
    end
  end
end

--- Renders the full output buffer for a kernel.
--- Clears the buffer and re-renders all In/Out blocks.
---@param kernel string
---@param full? boolean whether to display full output ignoring max_displayed_lines
function display.render_output(kernel, full)
  local w = Jupyterm.kernels[kernel].widget
  if not w then return end

  local bufnr = w.buf_nrs.output

  -- Get kernel data
  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local inputs = kernel_lines[1]
  local outputs = kernel_lines[2]

  local commentstring = Jupyterm.jupystring[bufnr]

  buf_helpers.with_modifiable(bufnr, function()
    -- Clear buffer and extmarks
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    vim.api.nvim_buf_clear_namespace(bufnr, Jupyterm.ns_in_top, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, Jupyterm.ns_in_bottom, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, Jupyterm.ns_out_top, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, Jupyterm.ns_out_bottom, 0, -1)

    -- Filter out variables command entries
    local vars_cmd = Jupyterm.config.ui.repl.variables.command
    local filtered_indices = {}
    for ind = 1, #inputs do
      if utils.strip(inputs[ind]) ~= vars_cmd then
        table.insert(filtered_indices, ind)
      end
    end

    -- Render blocks in reverse order (newest at bottom like a terminal)
    for rev = #filtered_indices, 1, -1 do
      local ind = filtered_indices[rev]
      local i = inputs[ind]
      local o = outputs[ind]

      -- Check for max displayed lines
      local buf_count = vim.api.nvim_buf_line_count(bufnr)
      if not full and buf_count > Jupyterm.config.ui.max_displayed_lines then
        break
      end

      -- Display outputs
      local split_o = utils.split_by_newlines(o)
      if #split_o > Jupyterm.config.ui.max_displayed_lines then
        split_o = { unpack(split_o, #split_o - Jupyterm.config.ui.max_displayed_lines + 1, #split_o) }
      end
      if (#split_o ~= 1) or (utils.strip(split_o[1]) ~= "") then
        local out_txt, out_txt2 = display.generate_cell(commentstring, ind, "Out")
        vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "" })
        out_txt2:render(bufnr, Jupyterm.ns_out_bottom, 2)
        vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, split_o)
        vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "" })
        out_txt:render(bufnr, Jupyterm.ns_out_top, 2)
      end

      -- Display inputs
      local split_i = utils.split_by_newlines(i)
      local in_txt, in_txt2 = display.generate_cell(commentstring, ind, "In")
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "" })
      in_txt2:render(bufnr, Jupyterm.ns_in_bottom, 2)
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, split_i)
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "" })
      in_txt:render(bufnr, Jupyterm.ns_in_top, 2)
    end
  end)
end

--- Updates the output buffer incrementally (used by refresh timer).
---@param kernel string
function display.update_output(kernel)
  local w = Jupyterm.kernels[kernel].widget
  if not w then return end

  local bufnr = w.buf_nrs.output
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local inputs = kernel_lines[1]
  local outputs = kernel_lines[2]

  -- Check if we need a full re-render (new entries added)
  local in_top_marks = vim.api.nvim_buf_get_extmarks(bufnr, Jupyterm.ns_in_top, 0, -1, { details = true })

  -- Count displayed entries (excluding ghost extmarks at row 0)
  local displayed_count = 0
  for _, e in ipairs(in_top_marks) do
    if e[2] ~= 0 then
      displayed_count = displayed_count + 1
    end
  end

  -- Count non-variables entries
  local vars_cmd = Jupyterm.config.ui.repl.variables.command
  local actual_count = 0
  for _, inp in ipairs(inputs) do
    if utils.strip(inp) ~= vars_cmd then
      actual_count = actual_count + 1
    end
  end

  -- If new entries exist, do full re-render
  if actual_count ~= displayed_count then
    display.render_output(kernel)
    -- Auto-scroll to bottom
    if w.win_nrs.output and vim.api.nvim_win_is_valid(w.win_nrs.output) then
      local buf_len = vim.api.nvim_buf_line_count(bufnr)
      pcall(vim.api.nvim_win_set_cursor, w.win_nrs.output, { buf_len, 0 })
    end
    return
  end

  -- Otherwise, update existing output cells in-place
  buf_helpers.with_modifiable(bufnr, function()
    for i = #in_top_marks - 1, 1, -1 do
      local e = in_top_marks[i]
      local extmark_row = e[2]
      local extmark_details = e[4]

      if extmark_row ~= 0 then
        local in_index = tonumber(string.match(extmark_details.virt_lines[2][1][1], "%d+"))

        -- Update output cell
        local out_top = utils.get_extmark_below_buf(bufnr, extmark_row, Jupyterm.ns_out_top)
        local out_bottom = utils.get_extmark_below_buf(bufnr, extmark_row, Jupyterm.ns_out_bottom)
        if out_top and out_bottom then
          local out_index = tonumber(string.match(out_top[4].virt_lines[2][1][1], "%d+"))
          if in_index == out_index then
            local split_output = utils.split_by_newlines(outputs[in_index])
            local previous_output = vim.api.nvim_buf_get_lines(bufnr, out_top[2] + 1, out_bottom[2], false)
            if table.concat(split_output, "\n") ~= table.concat(previous_output, "\n") then
              vim.api.nvim_buf_set_lines(bufnr, out_top[2] + 1, out_bottom[2], false, split_output)
            elseif (#previous_output == 1) and (utils.strip(previous_output[1]) == "") then
              vim.api.nvim_buf_set_lines(bufnr, out_top[2], out_bottom[2] + 1, false, {})
              vim.api.nvim_buf_del_extmark(bufnr, Jupyterm.ns_out_top, out_top[1])
              vim.api.nvim_buf_del_extmark(bufnr, Jupyterm.ns_out_bottom, out_bottom[1])
            end
          end
        end
      end
    end
  end)
end

--- Requests a variables update by sending the variables command.
---@param kernel string
function display.request_variables(kernel)
  if not Jupyterm.kernels[kernel] then return end
  local vars_cmd = Jupyterm.config.ui.repl.variables.command
  vim.fn.JupyEval(tostring(kernel), vars_cmd)
  local output_len = vim.fn.JupyOutputLen(tostring(kernel))
  Jupyterm.kernels[kernel].vars_output_idx = output_len
end

--- Updates the variables buffer display from the latest variables output.
---@param kernel string
function display.update_variables_display(kernel)
  local w = Jupyterm.kernels[kernel].widget
  if not w then return end

  local vars_idx = Jupyterm.kernels[kernel].vars_output_idx
  if not vars_idx then return end

  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local outputs = kernel_lines[2]
  local output = outputs[vars_idx]
  if not output then return end

  -- Don't update if still computing
  if string.match(output, Jupyterm.config.ui.wait_str) or string.match(output, Jupyterm.config.ui.queue_str) then
    return
  end

  local split_output = utils.split_by_newlines(output)
  -- Remove duration line if present
  if #split_output > 0 and string.match(split_output[#split_output], "^Duration:") then
    table.remove(split_output)
  end

  buf_helpers.with_modifiable(w.buf_nrs.variables, function(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, split_output)
  end)

  -- Resize the variables pane to fit content
  if w.win_nrs.variables and vim.api.nvim_win_is_valid(w.win_nrs.variables) then
    local widget_layout = require("jupyterm.widget_layout")
    widget_layout.open_variables(w.buf_nrs, w.win_nrs, Jupyterm.config.ui.repl.variables.max_height)
  end
end

--- Generates cell text
---@param commentstring string
---@param index integer cell number
---@param type string input or output cell - "In" or "Out" respectively
---@return Line
---@overload fun(commentstring: string, index: integer, type: string): Line,Line
---@private
function display.generate_cell(commentstring, index, type)
  local line1 = Line()
  line1:append(
    Text(
      commentstring,
      {
        hl_group = "Jupyterm" .. type .. "Text",
        hl_mode = "combine",
        hl_eol = true,
        virt_lines_above = true,
        virt_lines = {
          { {
            "───────────────────────────────────────────────────────────────",
            "Jupyterm" .. type .. "Text"
          } },
          { {
            string.format(type .. " [%s]: ", index),
            "Jupyterm" .. type .. "Text"
          } },
        }
      }
    ), {}
  )
  local line2 = Line()
  line2:append(
    Text(
      "```",
      {
        hl_group = "Jupyterm" .. type .. "Text",
        hl_mode = "combine",
      }
    ), {}
  )
  return line1, line2
end

--- Manually refreshes the output pane (full re-render).
---@param kernel? string
function display.refresh_output(kernel)
  if not kernel then
    kernel = utils.find_kernel(vim.api.nvim_get_current_buf())
  end
  kernel = kernel or utils.get_kernel(kernel)
  display.render_output(kernel)
  display.scroll_output_to_bottom(kernel)
end

--- Scrolls the output pane to the bottom.
---@param kernel string
function display.scroll_output_to_bottom(kernel)
  local w = Jupyterm.kernels[kernel].widget
  if not w then return end
  local winid = w.win_nrs.output
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  local bufnr = w.buf_nrs.output
  local buf_len = vim.api.nvim_buf_line_count(bufnr)
  -- Scroll without changing the current window
  local cur_win = vim.api.nvim_get_current_win()
  pcall(vim.api.nvim_win_set_cursor, winid, { buf_len, 0 })
  if vim.api.nvim_win_is_valid(cur_win) then
    pcall(vim.api.nvim_set_current_win, cur_win)
  end
end

--- Gets the filtered input history for a kernel (excludes variables commands).
---@param kernel string
---@return string[] inputs
---@private
function display._get_input_history(kernel)
  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local inputs = kernel_lines[1]
  local vars_cmd = Jupyterm.config.ui.repl.variables.command
  local filtered = {}
  for _, inp in ipairs(inputs) do
    if utils.strip(inp) ~= vars_cmd then
      table.insert(filtered, inp)
    end
  end
  return filtered
end

--- Navigates to the previous command in input history.
---@param kernel? string
function display.history_prev(kernel)
  if not kernel then
    kernel = utils.find_kernel(vim.api.nvim_get_current_buf())
  end
  kernel = kernel or utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  local history = display._get_input_history(kernel)
  if #history == 0 then return end

  local idx = Jupyterm.kernels[kernel].history_idx or (#history + 1)
  idx = idx - 1
  if idx < 1 then idx = 1 end
  Jupyterm.kernels[kernel].history_idx = idx

  local entry = history[idx]
  local lines = utils.split_by_newlines(entry)
  vim.api.nvim_buf_set_lines(w.buf_nrs.input, 0, -1, false, lines)
end

--- Navigates to the next command in input history.
---@param kernel? string
function display.history_next(kernel)
  if not kernel then
    kernel = utils.find_kernel(vim.api.nvim_get_current_buf())
  end
  kernel = kernel or utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  local history = display._get_input_history(kernel)
  if #history == 0 then return end

  local idx = Jupyterm.kernels[kernel].history_idx or (#history + 1)
  idx = idx + 1
  if idx > #history then
    -- Past the end: clear input buffer
    Jupyterm.kernels[kernel].history_idx = #history + 1
    vim.api.nvim_buf_set_lines(w.buf_nrs.input, 0, -1, false, {""})
    return
  end
  Jupyterm.kernels[kernel].history_idx = idx

  local entry = history[idx]
  local lines = utils.split_by_newlines(entry)
  vim.api.nvim_buf_set_lines(w.buf_nrs.input, 0, -1, false, lines)
end

--- Copies the input block under the cursor in the output pane to the input pane and starts editing.
---@param kernel? string
function display.yank_block_to_input(kernel)
  if not kernel then
    kernel = utils.find_kernel(vim.api.nvim_get_current_buf())
  end
  kernel = kernel or utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  local bufnr = w.buf_nrs.output
  local winid = w.win_nrs.output
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local top_in = utils.get_extmark_above_buf(bufnr, cursor[1], Jupyterm.ns_in_top)
  local bottom_in = utils.get_extmark_below_buf(bufnr, cursor[1], Jupyterm.ns_in_bottom)
  local top_out = utils.get_extmark_above_buf(bufnr, cursor[1], Jupyterm.ns_out_top)

  -- Don't yank from output sections
  if top_in and top_out and top_out[2] > top_in[2] then return end
  if not top_in then return end

  local top = top_in[2] + 1
  local bottom
  if bottom_in then
    bottom = bottom_in[2]
  else
    bottom = vim.api.nvim_buf_line_count(bufnr)
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, top, bottom, false)

  -- Strip trailing empty lines
  while #lines > 0 and utils.strip(lines[#lines]) == "" do
    table.remove(lines)
  end
  if #lines == 0 then return end

  -- Set input buffer content and focus it
  vim.api.nvim_buf_set_lines(w.buf_nrs.input, 0, -1, false, lines)
  if w.win_nrs.input and vim.api.nvim_win_is_valid(w.win_nrs.input) then
    vim.api.nvim_set_current_win(w.win_nrs.input)
    vim.api.nvim_win_set_cursor(w.win_nrs.input, { 1, 0 })
  end
end

--- Toggles a keymap help menu for repl
---@param kernel string?
function display.show_repl_help(kernel)
  kernel = utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  -- Collect all keymaps for display
  local all_keymaps = {}
  for _, k in ipairs(Jupyterm.config.ui.repl.input_keymaps or {}) do
    table.insert(all_keymaps, k)
  end
  for _, k in ipairs(Jupyterm.config.ui.repl.output_keymaps or {}) do
    table.insert(all_keymaps, k)
  end
  for _, k in ipairs(Jupyterm.config.ui.repl.global_keymaps or {}) do
    table.insert(all_keymaps, k)
  end

  local popup_opts = {
    position = {
      row = 2,
      col = 0,
    },
    anchor = "NW",
    relative = "cursor",
    size = {
      width = "50%",
      height = #all_keymaps,
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      buftype = "nofile",
      bufhidden = "hide",
      swapfile = false,
    },
    border = {
      style = "double",
      text = {
        top = "REPL Help",
        top_align = "center",
      },
    },
    enter = false,
    focusable = false,
  }
  local help_menu = Popup(popup_opts)
  for i, k in ipairs(all_keymaps) do
    local h = Line({
      Text(k[4], "Title"),
      Text(": ", "Title"),
      Text(k[2], "SpecialKey")
    })
    h:render(help_menu.bufnr, help_menu.ns_id, i)
  end
  local bufnr = vim.api.nvim_get_current_buf()

  local function dismiss()
    help_menu:unmount()
    pcall(vim.keymap.del, "n", "q", { buffer = bufnr })
    pcall(vim.keymap.del, "n", "<Esc>", { buffer = bufnr })
  end

  vim.keymap.set("n", "q", dismiss, { buffer = bufnr, nowait = true })
  vim.keymap.set("n", "<Esc>", dismiss, { buffer = bufnr, nowait = true })

  vim.api.nvim_create_autocmd({ "ModeChanged", "CursorMoved" }, {
    group = "Jupyterm",
    callback = dismiss,
    once = true,
    buffer = bufnr,
  })
  help_menu:mount()
end

--- Jumps to the previous display block in the output pane.
---@param kernel string?
function display.jump_display_block_up(kernel)
  kernel = utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  local winid = w.win_nrs.output
  local bufnr = w.buf_nrs.output
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  local cur_line = vim.api.nvim_win_get_cursor(winid)[1]
  local out_above = utils.get_extmark_above_buf(bufnr, cur_line, Jupyterm.ns_out_top)
  local in_above = utils.get_extmark_above_buf(bufnr, cur_line, Jupyterm.ns_in_top)

  local out_row = out_above and out_above[2]
  local in_row = in_above and in_above[2]

  if out_row and in_row and (in_row > out_row) then
    cur_line = in_row - 1
  elseif out_row then
    cur_line = out_row
  elseif in_row then
    cur_line = in_row - 1
  else
    return
  end

  in_above = utils.get_extmark_above_buf(bufnr, cur_line, Jupyterm.ns_in_top)
  if in_above then
    vim.api.nvim_win_set_cursor(winid, { in_above[2] + 2, 0 })
  end
end

--- Jumps to the next display block in the output pane.
---@param kernel string?
function display.jump_display_block_down(kernel)
  kernel = utils.get_kernel(kernel)
  local w = Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget
  if not w then return end

  local winid = w.win_nrs.output
  local bufnr = w.buf_nrs.output
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  local cur_line = vim.api.nvim_win_get_cursor(winid)[1]
  local in_below = utils.get_extmark_below_buf(bufnr, cur_line, Jupyterm.ns_in_top)
  if in_below then
    vim.api.nvim_win_set_cursor(winid, { in_below[2] + 2, 0 })
  end
end

-- =========================================================================
-- Virtual text functions (unchanged — operate on source code buffers)
-- =========================================================================

--- Toggles virtual text.
---@param kernel string?
function display.toggle_virt_text(kernel)
  kernel = utils.get_kernel(kernel)

  -- Auto start if not started
  if not Jupyterm.kernels[kernel] then
    local ft = vim.bo.filetype
    local kernel_name = Jupyterm.lang_to_kernel[ft] or Jupyterm.lang_to_kernel["python"]
    local manage_kernels = require("jupyterm.manage_kernels")
    manage_kernels.start_kernel(nil, nil, kernel_name)
  end

  if utils.is_virt_text_showing(kernel) then
    display.hide_all_virt_text(kernel)
    Jupyterm.kernels[kernel].show_virt = false
  else
    display.show_all_virt_text(kernel)
    Jupyterm.kernels[kernel].show_virt = true
  end
end

--- Shows all virtual text.
---@param kernel string
function display.show_all_virt_text(kernel)
  for oloc = 1, vim.fn.JupyOutputLen(tostring(kernel)) do
    local vt = Jupyterm.kernels[kernel].virt_text[oloc]
    if vt then
      display.show_virt_text(kernel, oloc, vt.start_row, vt.end_row, vt.start_col, vt.end_col, vt.hl)
    end
  end
end

--- Hides all virtual text.
---@param kernel string
function display.hide_all_virt_text(kernel)
  vim.api.nvim_buf_clear_namespace(
    Jupyterm.kernels[kernel].virt_buf,
    Jupyterm.ns_virt,
    0,
    -1
  )
  Jupyterm.kernels[kernel].virt_olocs = {}
  Jupyterm.kernels[kernel].virt_extmarks = {}
end

--- Updates all virtual text.
---@param kernel string
---@private
function display.update_all_virt_text(kernel)
  local buf = Jupyterm.kernels[kernel].virt_buf
  local olocs = Jupyterm.kernels[kernel].virt_olocs
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, Jupyterm.ns_virt, 0, -1, { details = true })
  local outputs = vim.fn.JupyOutput(tostring(kernel))[2]
  for _, e in ipairs(extmarks) do
    local oloc = olocs[e[1]]

    local vl = outputs[oloc] or ""
    local text_hl_group = "JupytermVirtQueued"
    if string.match(vl, Jupyterm.config.ui.wait_str) then
      text_hl_group = "JupytermVirtComputing"
    elseif string.match(vl, "Error") then
      text_hl_group = "JupytermVirtError"
    else
      text_hl_group = "JupytermVirtCompleted"
    end

    local formatted_output = display.split_virt_text(outputs[oloc], text_hl_group)
    if e[#e].virt_lines then
      vim.api.nvim_buf_set_extmark(buf, Jupyterm.ns_virt, e[2], e[3], {
        id = e[1],
        end_row = e[#e].end_row,
        end_col = e[#e].end_col,
        virt_lines = formatted_output,
        sign_text = e[#e].sign_text,
        sign_hl_group = text_hl_group,
        hl_group = e[#e].hl_group,
        invalidate = true,
        undo_restore = false,
      })
    else
      vim.api.nvim_buf_set_extmark(buf, Jupyterm.ns_virt, e[2], e[3], {
        id = e[1],
        sign_text = e[#e].sign_text,
        sign_hl_group = text_hl_group,
        hl_group = e[#e].hl_group,
        invalidate = true,
        undo_restore = false,
      })
    end
  end
end

--- Shows virtual text corresponding to a kernel output at rows/cols specified.
---@param kernel string
---@param output_num integer? kernel output number
---@param start_row integer
---@param end_row integer
---@param start_col integer?
---@param end_col integer?
---@param hl string? highlight group
---@private
function display.show_virt_text(kernel, output_num, start_row, end_row, start_col, end_col, hl)
  display.delete_virt_text(kernel, start_row, end_row)

  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local output = kernel_lines[2]
  local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1]
  local line_len = string.len(end_line)
  output_num = output_num or #output

  for row = start_row, end_row do
    local virt_id = nil

    local vl = output[output_num] or ""
    local text_hl_group = "JupytermVirtQueued"
    if string.match(vl, Jupyterm.config.ui.wait_str) then
      text_hl_group = "JupytermVirtComputing"
    elseif string.match(vl, "Error") then
      text_hl_group = "JupytermVirtError"
    else
      text_hl_group = "JupytermVirtCompleted"
    end

    local formatted_output = display.split_virt_text(output[output_num], text_hl_group)
    if row == end_row then
      start_col = start_col or 0
      end_col = end_col or line_len
      virt_id = vim.api.nvim_buf_set_extmark(0, Jupyterm.ns_virt, row, start_col, {
        end_col = end_col,
        virt_lines = formatted_output,
        sign_text = string.sub(tostring(output_num), -2, -1),
        sign_hl_group = text_hl_group,
        hl_group = hl,
        invalidate = true,
        undo_restore = false,
      })
    else
      virt_id = vim.api.nvim_buf_set_extmark(0, Jupyterm.ns_virt, row, 0, {
        sign_text = string.sub(tostring(output_num), -2, -1),
        sign_hl_group = text_hl_group,
        hl_group = hl,
        invalidate = true,
        undo_restore = false,
      })
    end
    Jupyterm.kernels[kernel].virt_olocs[virt_id] = output_num
    if Jupyterm.kernels[kernel].virt_extmarks[output_num] then
      table.insert(Jupyterm.kernels[kernel].virt_extmarks[output_num], virt_id)
    else
      Jupyterm.kernels[kernel].virt_extmarks[output_num] = { virt_id }
    end
  end
  Jupyterm.kernels[kernel].virt_buf = vim.api.nvim_get_current_buf()
end

---Toggles virtual text at row (or under cursor)
---@param kernel? string
---@param row? integer
function display.toggle_virt_text_at_row(kernel, row)
  kernel = utils.get_kernel(kernel)
  row = row or vim.api.nvim_win_get_cursor(0)[1] - 1

  local overlap_extmark = vim.api.nvim_buf_get_extmarks(
    0,
    Jupyterm.ns_virt,
    { row, 0 },
    { row, 0 },
    { details = true }
  )

  local lines_showing = false

  if #overlap_extmark > 0 then
    local oe = overlap_extmark[1]
    local oloc = Jupyterm.kernels[kernel].virt_olocs[oe[1]]
    local extmarks = Jupyterm.kernels[kernel].virt_extmarks[oloc]
    for _, e_id in ipairs(extmarks) do
      local e = vim.api.nvim_buf_get_extmark_by_id(0, Jupyterm.ns_virt, e_id, { details = true })
      if e[#e].virt_lines then
        lines_showing = true
      end
    end
  end

  if lines_showing then
    display.hide_virt_text_at_row(kernel, row)
  else
    display.show_virt_text_at_row(kernel, row)
  end
end

--- Deletes virtual text in range.
---@param kernel string
---@param start_row? integer
---@param end_row? integer
---@private
function display.delete_virt_text(kernel, start_row, end_row)
  start_row = start_row or vim.api.nvim_win_get_cursor(0)[1] - 1
  end_row = end_row or start_row

  local overlap_extmarks = vim.api.nvim_buf_get_extmarks(0, Jupyterm.ns_virt, { start_row, 0 }, { end_row, 0 }, { details = true })
  for _, oe in ipairs(overlap_extmarks) do
    local oloc = Jupyterm.kernels[kernel].virt_olocs[oe[1]]
    if Jupyterm.kernels[kernel].virt_extmarks[oloc] then
      for _, e_id in ipairs(Jupyterm.kernels[kernel].virt_extmarks[oloc]) do
        vim.api.nvim_buf_del_extmark(0, Jupyterm.ns_virt, e_id)
        Jupyterm.kernels[kernel].virt_olocs[e_id] = nil
      end
      Jupyterm.kernels[kernel].virt_extmarks[oloc] = {}
    end
  end
end

--- Hides virtual text at row.
---@param kernel string
---@param row? integer
---@private
function display.hide_virt_text_at_row(kernel, row)
  row = row or vim.api.nvim_win_get_cursor(0)[1] - 1

  local overlap_extmarks = vim.api.nvim_buf_get_extmarks(0, Jupyterm.ns_virt, { row, 0 }, { row, 0 }, { details = true })
  for _, oe in ipairs(overlap_extmarks) do
    local oloc = Jupyterm.kernels[kernel].virt_olocs[oe[1]]
    local extmarks = Jupyterm.kernels[kernel].virt_extmarks[oloc]
    for _, e_id in ipairs(extmarks) do
      local e = vim.api.nvim_buf_get_extmark_by_id(0, Jupyterm.ns_virt, e_id, { details = true })
      vim.api.nvim_buf_set_extmark(0, Jupyterm.ns_virt, e[1], e[2], {
        id = e_id,
        sign_text = string.sub(tostring(oloc), -2, -1),
        sign_hl_group = e[#e].sign_hl_group,
        hl_group = e[#e].hl_group,
        invalidate = true,
        undo_restore = false,
      })
    end
  end
end

--- Shows virtual text at a specific row.
---@param kernel string
---@param row? integer
---@private
function display.show_virt_text_at_row(kernel, row)
  row = row or vim.api.nvim_win_get_cursor(0)[1] - 1

  for oloc = vim.fn.JupyOutputLen(tostring(kernel)), 1, -1 do
    local vt = Jupyterm.kernels[kernel].virt_text[oloc]
    if vt and (row >= vt.start_row) and (row <= vt.end_row) then
      display.show_virt_text(kernel, oloc, vt.start_row, vt.end_row, vt.start_col, vt.end_col, vt.hl)
      return
    end
  end
end

--- Splits virtual text by newlines into a table of lines for virt_lines.
---@param text string text to split
---@param hl string hl group for the text
---@return table? table of lines with highlight info
---@private
function display.split_virt_text(text, hl)
  local split_text = utils.split_by_newlines(text)
  local result = {}
  for _, st in ipairs(split_text) do
    table.insert(result, { { st, hl } })
  end
  if #result == 1 then
    if result[1][1][1] ~= "" then
      return result
    end
  else
    return result
  end
end

--- Expands virtual text into a popup.
---@param kernel? string
---@param row? integer
function display.expand_virt_text(kernel, row)
  kernel = utils.get_kernel(kernel)
  row = row or vim.api.nvim_win_get_cursor(0)[1] - 1

  local buf = Jupyterm.kernels[kernel].virt_buf
  local extmark = vim.api.nvim_buf_get_extmarks(buf, Jupyterm.ns_virt, { row, 0 }, { row, -1 }, { details = true })[1]
  local oloc = Jupyterm.kernels[kernel].virt_olocs[extmark[1]]
  local output = vim.fn.JupyOutput(tostring(kernel))[2][oloc]
  local kernel_name = Jupyterm.kernels[kernel].kernel_name
  local popup = Popup({
    position = {
      row = 0,
      col = 0,
    },
    anchor = "NW",
    relative = "cursor",
    size = {
      width = "100%",
      height = "25%",
    },
    enter = true,
    focusable = true,
    buf_options = {
      buftype = "nofile",
      bufhidden = "hide",
      swapfile = false,
      filetype = "jupyterm-" .. kernel_name
    },
    win_options = {
      winhighlight = "FloatBorder:" .. extmark[4].sign_hl_group,
    },
    border = {
      style = "double"
    }
  })
  popup:mount()
  popup:on("BufLeave", function()
    popup:unmount()
  end, { once = true })
  local split_output = utils.split_by_newlines(output)
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, split_output)
end

return display