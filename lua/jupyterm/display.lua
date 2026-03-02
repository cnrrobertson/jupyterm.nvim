---@tag Jupyterm.display
---@signature Jupyterm.display
local Line = require("nui.line")
local Text = require("nui.text")
local Popup = require("nui.popup")

local utils = require("jupyterm.utils")
local buf_helpers = require("jupyterm.buf_helpers")

local display = {}

-- =========================================================================
-- Helpers
-- =========================================================================

--- Resolves kernel from argument or current buffer.
---@param kernel string?
---@return string
local function resolve_kernel(kernel)
  if not kernel then
    kernel = utils.find_kernel(vim.api.nvim_get_current_buf())
  end
  return kernel or utils.get_kernel(kernel)
end

--- Returns the highlight group for a virt-text output string.
---@param text string
---@return string
local function virt_hl(text)
  if string.match(text, Jupyterm.config.ui.wait_str) then
    return "JupytermVirtComputing"
  elseif string.match(text, "Error") then
    return "JupytermVirtError"
  else
    return "JupytermVirtCompleted"
  end
end

--- Returns the output widget for a kernel, or nil.
---@param kernel string
---@return { buf_nrs: table, win_nrs: table }?
local function get_widget(kernel)
  return Jupyterm.kernels[kernel] and Jupyterm.kernels[kernel].widget or nil
end

-- =========================================================================
-- Refresh
-- =========================================================================

--- Refreshes all output windows.
function display.refresh_windows()
  for k, _ in pairs(Jupyterm.kernels) do
    local w = get_widget(k)
    if w and w.win_nrs.output and vim.api.nvim_win_is_valid(w.win_nrs.output) then
      display.update_output(k)
    end
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

-- =========================================================================
-- Output pane rendering
-- =========================================================================

--- Generates the top and bottom extmark Lines for an In/Out cell header.
---@param commentstring string
---@param index integer
---@param kind string "In" or "Out"
---@return Line, Line
function display.generate_cell(commentstring, index, kind)
  local hl = "Jupyterm" .. kind .. "Text"
  local line1 = Line()
  line1:append(Text(commentstring, {
    hl_group = hl, hl_mode = "combine", hl_eol = true,
    virt_lines_above = true,
    virt_lines = {
      { { "───────────────────────────────────────────────────────────────", hl } },
      { { string.format("%s [%s]: ", kind, index), hl } },
    },
  }), {})
  local line2 = Line()
  line2:append(Text("```", { hl_group = hl, hl_mode = "combine" }), {})
  return line1, line2
end

--- Renders the full output buffer for a kernel.
---@param kernel string
---@param full? boolean ignore max_displayed_lines when true
function display.render_output(kernel, full)
  local w = Jupyterm.kernels[kernel].widget
  if not w then return end

  local bufnr = w.buf_nrs.output
  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local inputs, outputs = kernel_lines[1], kernel_lines[2]
  local commentstring = Jupyterm.jupystring[bufnr]

  local expand_key = "x"
  for _, km in ipairs(Jupyterm.config.ui.repl.output_keymaps or {}) do
    if km[4] == "Expand output" then expand_key = km[2]; break end
  end

  local TRUNC_SENTINEL = "<<jupyterm-trunc>>"

  buf_helpers.with_modifiable(bufnr, function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    for _, ns in ipairs({ Jupyterm.ns_in_top, Jupyterm.ns_in_bottom,
                          Jupyterm.ns_out_top, Jupyterm.ns_out_bottom,
                          Jupyterm.ns_trunc }) do
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end

    local vars_cmd = Jupyterm.config.ui.repl.variables.command
    local filtered = {}
    for ind = 1, #inputs do
      if utils.strip(inputs[ind]) ~= vars_cmd then
        table.insert(filtered, ind)
      end
    end

    for rev = #filtered, 1, -1 do
      local ind = filtered[rev]
      if not full and vim.api.nvim_buf_line_count(bufnr) > Jupyterm.config.ui.max_displayed_lines then
        break
      end

      -- Output block
      local split_o = utils.split_by_newlines(outputs[ind])
      if #split_o > Jupyterm.config.ui.max_displayed_lines then
        split_o = { unpack(split_o, #split_o - Jupyterm.config.ui.max_displayed_lines + 1, #split_o) }
      end
      local max_out = Jupyterm.config.ui.repl.max_output_lines
      if max_out and #split_o > max_out then
        local hidden = #split_o - max_out
        split_o = { unpack(split_o, 1, max_out) }
        table.insert(split_o, TRUNC_SENTINEL .. hidden)
      end
      if (#split_o ~= 1) or (utils.strip(split_o[1]) ~= "") then
        local top, bot = display.generate_cell(commentstring, ind, "Out")
        vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "" })
        bot:render(bufnr, Jupyterm.ns_out_bottom, 2)
        vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, split_o)
        vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "" })
        top:render(bufnr, Jupyterm.ns_out_top, 2)
      end

      -- Input block
      local split_i = utils.split_by_newlines(inputs[ind])
      local top, bot = display.generate_cell(commentstring, ind, "In")
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "" })
      bot:render(bufnr, Jupyterm.ns_in_bottom, 2)
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, split_i)
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "" })
      top:render(bufnr, Jupyterm.ns_in_top, 2)
    end
  end)

  -- Style truncation sentinel lines with a Comment-highlighted virt_text overlay
  buf_helpers.with_modifiable(bufnr, function()
    for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if vim.startswith(line, TRUNC_SENTINEL) then
        local hidden = tonumber(line:sub(#TRUNC_SENTINEL + 1)) or 0
        vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { "" })
        vim.api.nvim_buf_set_extmark(bufnr, Jupyterm.ns_trunc, lnum - 1, 0, {
          virt_text = { { string.format("  ↕ %d more lines  (%s to expand)", hidden, expand_key), "Comment" } },
          virt_text_pos = "overlay",
          hl_mode = "replace",
        })
      end
    end
  end)
end

--- Updates the output buffer incrementally (used by refresh timer).
---@param kernel string
function display.update_output(kernel)
  local w = get_widget(kernel)
  if not w then return end

  local bufnr = w.buf_nrs.output
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local inputs, outputs = kernel_lines[1], kernel_lines[2]

  local in_top_marks = vim.api.nvim_buf_get_extmarks(bufnr, Jupyterm.ns_in_top, 0, -1, { details = true })

  local displayed_count = 0
  for _, e in ipairs(in_top_marks) do
    if e[2] ~= 0 then displayed_count = displayed_count + 1 end
  end

  local vars_cmd = Jupyterm.config.ui.repl.variables.command
  local actual_count = 0
  for _, inp in ipairs(inputs) do
    if utils.strip(inp) ~= vars_cmd then actual_count = actual_count + 1 end
  end

  if actual_count ~= displayed_count then
    display.render_output(kernel)
    if w.win_nrs.output and vim.api.nvim_win_is_valid(w.win_nrs.output) then
      pcall(vim.api.nvim_win_set_cursor, w.win_nrs.output, { vim.api.nvim_buf_line_count(bufnr), 0 })
    end
    return
  end

  buf_helpers.with_modifiable(bufnr, function()
    for i = #in_top_marks - 1, 1, -1 do
      local e = in_top_marks[i]
      local extmark_row = e[2]
      if extmark_row ~= 0 then
        local in_index = tonumber(string.match(e[4].virt_lines[2][1][1], "%d+"))
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

--- Manually refreshes the output pane (full re-render).
---@param kernel? string
function display.refresh_output(kernel)
  kernel = resolve_kernel(kernel)
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
  local cur_win = vim.api.nvim_get_current_win()
  pcall(vim.api.nvim_win_set_cursor, winid, { vim.api.nvim_buf_line_count(w.buf_nrs.output), 0 })
  if vim.api.nvim_win_is_valid(cur_win) then
    pcall(vim.api.nvim_set_current_win, cur_win)
  end
end

-- =========================================================================
-- Variables pane
-- =========================================================================

--- Requests a variables update by sending the variables command.
---@param kernel string
function display.request_variables(kernel)
  if not Jupyterm.kernels[kernel] then return end
  local vars_cmd = Jupyterm.config.ui.repl.variables.command
  vim.fn.JupyEval(tostring(kernel), vars_cmd)
  Jupyterm.kernels[kernel].vars_output_idx = vim.fn.JupyOutputLen(tostring(kernel))
end

--- Updates the variables buffer display from the latest variables output.
---@param kernel string
function display.update_variables_display(kernel)
  local w = get_widget(kernel)
  if not w then return end

  local vars_idx = Jupyterm.kernels[kernel].vars_output_idx
  if not vars_idx then return end

  local output = vim.fn.JupyOutput(tostring(kernel))[2][vars_idx]
  if not output then return end
  if string.match(output, Jupyterm.config.ui.wait_str) or string.match(output, Jupyterm.config.ui.queue_str) then
    return
  end

  local split_output = utils.split_by_newlines(output)
  if #split_output > 0 and string.match(split_output[#split_output], "^Duration:") then
    table.remove(split_output)
  end

  buf_helpers.with_modifiable(w.buf_nrs.variables, function(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, split_output)
  end)

  if w.win_nrs.variables and vim.api.nvim_win_is_valid(w.win_nrs.variables) then
    require("jupyterm.widget_layout").open_variables(w.buf_nrs, w.win_nrs, Jupyterm.config.ui.repl.variables.max_height)
  end
end

-- =========================================================================
-- Input history
-- =========================================================================

--- Returns filtered input history for a kernel (excludes variables commands).
---@param kernel string
---@return string[]
function display._get_input_history(kernel)
  local inputs = vim.fn.JupyOutput(tostring(kernel))[1]
  local vars_cmd = Jupyterm.config.ui.repl.variables.command
  local filtered = {}
  for _, inp in ipairs(inputs) do
    if utils.strip(inp) ~= vars_cmd then table.insert(filtered, inp) end
  end
  return filtered
end

--- Navigates to the previous command in input history.
---@param kernel? string
function display.history_prev(kernel)
  kernel = resolve_kernel(kernel)
  local w = get_widget(kernel)
  if not w then return end
  local history = display._get_input_history(kernel)
  if #history == 0 then return end
  local idx = math.max((Jupyterm.kernels[kernel].history_idx or (#history + 1)) - 1, 1)
  Jupyterm.kernels[kernel].history_idx = idx
  vim.api.nvim_buf_set_lines(w.buf_nrs.input, 0, -1, false, utils.split_by_newlines(history[idx]))
end

--- Navigates to the next command in input history.
---@param kernel? string
function display.history_next(kernel)
  kernel = resolve_kernel(kernel)
  local w = get_widget(kernel)
  if not w then return end
  local history = display._get_input_history(kernel)
  if #history == 0 then return end
  local idx = (Jupyterm.kernels[kernel].history_idx or (#history + 1)) + 1
  if idx > #history then
    Jupyterm.kernels[kernel].history_idx = #history + 1
    vim.api.nvim_buf_set_lines(w.buf_nrs.input, 0, -1, false, { "" })
    return
  end
  Jupyterm.kernels[kernel].history_idx = idx
  vim.api.nvim_buf_set_lines(w.buf_nrs.input, 0, -1, false, utils.split_by_newlines(history[idx]))
end

-- =========================================================================
-- Output pane interactions
-- =========================================================================

--- Copies the input block under the cursor to the input pane for editing.
---@param kernel? string
function display.yank_block_to_input(kernel)
  kernel = resolve_kernel(kernel)
  local w = get_widget(kernel)
  if not w then return end

  local bufnr = w.buf_nrs.output
  local winid = w.win_nrs.output
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local top_in  = utils.get_extmark_above_buf(bufnr, cursor[1], Jupyterm.ns_in_top)
  local bot_in  = utils.get_extmark_below_buf(bufnr, cursor[1], Jupyterm.ns_in_bottom)
  local top_out = utils.get_extmark_above_buf(bufnr, cursor[1], Jupyterm.ns_out_top)

  if not top_in then return end
  if top_in and top_out and top_out[2] > top_in[2] then return end

  local bottom = bot_in and bot_in[2] or vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, top_in[2] + 1, bottom, false)
  while #lines > 0 and utils.strip(lines[#lines]) == "" do table.remove(lines) end
  if #lines == 0 then return end

  vim.api.nvim_buf_set_lines(w.buf_nrs.input, 0, -1, false, lines)
  if w.win_nrs.input and vim.api.nvim_win_is_valid(w.win_nrs.input) then
    vim.api.nvim_set_current_win(w.win_nrs.input)
    vim.api.nvim_win_set_cursor(w.win_nrs.input, { 1, 0 })
  end
end

--- Opens the full output of the block under the cursor in a floating popup.
---@param kernel? string
function display.expand_output_block(kernel)
  kernel = resolve_kernel(kernel)
  local w = get_widget(kernel)
  if not w then return end

  local bufnr = w.buf_nrs.output
  local winid = w.win_nrs.output
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local top_out = utils.get_extmark_above_buf(bufnr, cursor[1], Jupyterm.ns_out_top)
  if not top_out then return end

  local ind = tonumber(string.match(top_out[4].virt_lines[2][1][1], "%d+"))
  if not ind then return end

  local output = vim.fn.JupyOutput(tostring(kernel))[2][ind]
  if not output then return end

  local lines = utils.split_by_newlines(output)
  while #lines > 0 and utils.strip(lines[#lines]) == "" do table.remove(lines) end
  if #lines == 0 then return end

  local height = math.min(math.max(#lines, 5), math.floor(vim.o.lines * 0.6))
  local popup = Popup({
    relative = "editor", position = "50%",
    size = { width = "70%", height = height },
    enter = true, focusable = true,
    buf_options = {
      buftype = "nofile", bufhidden = "wipe", swapfile = false,
      filetype = "jupyterm-repl-" .. Jupyterm.kernels[kernel].kernel_name,
    },
    border = { style = "rounded", text = {
      top = string.format(" Out [%d] ", ind), top_align = "center",
      bottom = " <Esc> close ", bottom_align = "center",
    }},
  })
  popup:mount()
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = popup.bufnr })

  local function close() popup:unmount() end
  popup:map("n", "<Esc>", close, {}, true)
  vim.api.nvim_create_autocmd("BufLeave", { buffer = popup.bufnr, once = true, callback = close })
end

--- Shows a keymap help popup for the current pane.
---@param kernel? string
function display.show_repl_help(kernel)
  kernel = utils.get_kernel(kernel)
  local w = get_widget(kernel)
  if not w then return end

  local cur_buf = vim.api.nvim_get_current_buf()
  local pane_keymaps = (cur_buf == w.buf_nrs.output)
    and Jupyterm.config.ui.repl.output_keymaps
    or  Jupyterm.config.ui.repl.input_keymaps

  local all_keymaps = {}
  for _, k in ipairs(pane_keymaps or {}) do table.insert(all_keymaps, k) end
  for _, k in ipairs(Jupyterm.config.ui.repl.global_keymaps or {}) do table.insert(all_keymaps, k) end

  local help_menu = Popup({
    anchor = "NW", relative = "cursor",
    position = { row = 2, col = 0 },
    size = { width = "50%", height = #all_keymaps },
    buf_options = { modifiable = false, readonly = true, buftype = "nofile", bufhidden = "hide", swapfile = false },
    border = { style = "double", text = { top = "REPL Help", top_align = "center" } },
    enter = false, focusable = false,
  })
  for i, k in ipairs(all_keymaps) do
    Line({ Text(k[4], "Title"), Text(": ", "Title"), Text(k[2], "SpecialKey") })
      :render(help_menu.bufnr, help_menu.ns_id, i)
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local function dismiss()
    help_menu:unmount()
    pcall(vim.keymap.del, "n", "<Esc>", { buffer = bufnr })
  end
  vim.keymap.set("n", "<Esc>", dismiss, { buffer = bufnr, nowait = true })
  vim.api.nvim_create_autocmd({ "ModeChanged", "CursorMoved" }, {
    group = "Jupyterm", once = true, buffer = bufnr, callback = dismiss,
  })
  help_menu:mount()
end

--- Jumps to the previous In block in the output pane.
---@param kernel? string
function display.jump_display_block_up(kernel)
  kernel = utils.get_kernel(kernel)
  local w = get_widget(kernel)
  if not w then return end

  local winid = w.win_nrs.output
  local bufnr = w.buf_nrs.output
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  local cur_line = vim.api.nvim_win_get_cursor(winid)[1]
  local out_row = (utils.get_extmark_above_buf(bufnr, cur_line, Jupyterm.ns_out_top) or {})[2]
  local in_row  = (utils.get_extmark_above_buf(bufnr, cur_line, Jupyterm.ns_in_top)  or {})[2]

  if out_row and in_row and in_row > out_row then
    cur_line = in_row - 1
  elseif out_row then
    cur_line = out_row
  elseif in_row then
    cur_line = in_row - 1
  else
    return
  end

  local mark = utils.get_extmark_above_buf(bufnr, cur_line, Jupyterm.ns_in_top)
  if mark then vim.api.nvim_win_set_cursor(winid, { mark[2] + 2, 0 }) end
end

--- Jumps to the next In block in the output pane.
---@param kernel? string
function display.jump_display_block_down(kernel)
  kernel = utils.get_kernel(kernel)
  local w = get_widget(kernel)
  if not w then return end

  local winid = w.win_nrs.output
  local bufnr = w.buf_nrs.output
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  local mark = utils.get_extmark_below_buf(bufnr, vim.api.nvim_win_get_cursor(winid)[1], Jupyterm.ns_in_top)
  if mark then vim.api.nvim_win_set_cursor(winid, { mark[2] + 2, 0 }) end
end

-- =========================================================================
-- Virtual text (inline outputs in source buffers)
-- =========================================================================

--- Toggles virtual text display for a kernel.
---@param kernel? string
function display.toggle_virt_text(kernel)
  kernel = utils.get_kernel(kernel)
  if not Jupyterm.kernels[kernel] then
    local kernel_name = Jupyterm.lang_to_kernel[vim.bo.filetype] or Jupyterm.lang_to_kernel["python"]
    require("jupyterm.manage_kernels").start_kernel(nil, nil, kernel_name)
  end
  if utils.is_virt_text_showing(kernel) then
    display.hide_all_virt_text(kernel)
    Jupyterm.kernels[kernel].show_virt = false
  else
    display.show_all_virt_text(kernel)
    Jupyterm.kernels[kernel].show_virt = true
  end
end

--- Shows all virtual text for a kernel.
---@param kernel string
function display.show_all_virt_text(kernel)
  for oloc = 1, vim.fn.JupyOutputLen(tostring(kernel)) do
    local vt = Jupyterm.kernels[kernel].virt_text[oloc]
    if vt then
      display.show_virt_text(kernel, oloc, vt.start_row, vt.end_row, vt.start_col, vt.end_col, vt.hl)
    end
  end
end

--- Hides all virtual text for a kernel.
---@param kernel string
function display.hide_all_virt_text(kernel)
  vim.api.nvim_buf_clear_namespace(Jupyterm.kernels[kernel].virt_buf, Jupyterm.ns_virt, 0, -1)
  Jupyterm.kernels[kernel].virt_olocs   = {}
  Jupyterm.kernels[kernel].virt_extmarks = {}
end

--- Updates all virtual text extmarks in-place.
---@param kernel string
function display.update_all_virt_text(kernel)
  local buf     = Jupyterm.kernels[kernel].virt_buf
  local olocs   = Jupyterm.kernels[kernel].virt_olocs
  local outputs = vim.fn.JupyOutput(tostring(kernel))[2]
  for _, e in ipairs(vim.api.nvim_buf_get_extmarks(buf, Jupyterm.ns_virt, 0, -1, { details = true })) do
    local oloc = olocs[e[1]]
    local hl   = virt_hl(outputs[oloc] or "")
    local opts = {
      id = e[1], sign_text = e[4].sign_text, sign_hl_group = hl,
      hl_group = e[4].hl_group, invalidate = true, undo_restore = false,
    }
    if e[4].virt_lines then
      opts.end_row = e[4].end_row; opts.end_col = e[4].end_col
      opts.virt_lines = display.split_virt_text(outputs[oloc], hl)
    end
    vim.api.nvim_buf_set_extmark(buf, Jupyterm.ns_virt, e[2], e[3], opts)
  end
end

--- Shows virtual text for a kernel output at the specified source range.
---@param kernel string
---@param output_num integer?
---@param start_row integer
---@param end_row integer
---@param start_col integer?
---@param end_col integer?
---@param hl string?
function display.show_virt_text(kernel, output_num, start_row, end_row, start_col, end_col, hl)
  display.delete_virt_text(kernel, start_row, end_row)

  local output = vim.fn.JupyOutput(tostring(kernel))[2]
  local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1]
  output_num = output_num or #output

  local text_hl = virt_hl(output[output_num] or "")
  local formatted = display.split_virt_text(output[output_num], text_hl)
  local sign = string.sub(tostring(output_num), -2, -1)

  for row = start_row, end_row do
    local opts = {
      sign_text = sign, sign_hl_group = text_hl,
      hl_group = hl, invalidate = true, undo_restore = false,
    }
    if row == end_row then
      start_col = start_col or 0
      end_col   = end_col   or string.len(end_line)
      opts.end_col    = end_col
      opts.virt_lines = formatted
    end
    local virt_id = vim.api.nvim_buf_set_extmark(0, Jupyterm.ns_virt, row, row == end_row and start_col or 0, opts)
    Jupyterm.kernels[kernel].virt_olocs[virt_id] = output_num
    if Jupyterm.kernels[kernel].virt_extmarks[output_num] then
      table.insert(Jupyterm.kernels[kernel].virt_extmarks[output_num], virt_id)
    else
      Jupyterm.kernels[kernel].virt_extmarks[output_num] = { virt_id }
    end
  end
  Jupyterm.kernels[kernel].virt_buf = vim.api.nvim_get_current_buf()
end

--- Toggles virtual text at a row (or cursor row).
---@param kernel? string
---@param row? integer
function display.toggle_virt_text_at_row(kernel, row)
  kernel = utils.get_kernel(kernel)
  row = row or vim.api.nvim_win_get_cursor(0)[1] - 1

  local overlap = vim.api.nvim_buf_get_extmarks(0, Jupyterm.ns_virt, { row, 0 }, { row, 0 }, { details = true })
  local showing = false
  if #overlap > 0 then
    local oloc = Jupyterm.kernels[kernel].virt_olocs[overlap[1][1]]
    for _, e_id in ipairs(Jupyterm.kernels[kernel].virt_extmarks[oloc] or {}) do
      if vim.api.nvim_buf_get_extmark_by_id(0, Jupyterm.ns_virt, e_id, { details = true })[3].virt_lines then
        showing = true; break
      end
    end
  end
  if showing then display.hide_virt_text_at_row(kernel, row)
  else            display.show_virt_text_at_row(kernel, row) end
end

--- Deletes virtual text extmarks in a row range.
---@param kernel string
---@param start_row? integer
---@param end_row? integer
function display.delete_virt_text(kernel, start_row, end_row)
  start_row = start_row or vim.api.nvim_win_get_cursor(0)[1] - 1
  end_row   = end_row   or start_row
  for _, oe in ipairs(vim.api.nvim_buf_get_extmarks(0, Jupyterm.ns_virt, { start_row, 0 }, { end_row, 0 }, { details = true })) do
    local oloc = Jupyterm.kernels[kernel].virt_olocs[oe[1]]
    for _, e_id in ipairs(Jupyterm.kernels[kernel].virt_extmarks[oloc] or {}) do
      vim.api.nvim_buf_del_extmark(0, Jupyterm.ns_virt, e_id)
      Jupyterm.kernels[kernel].virt_olocs[e_id] = nil
    end
    Jupyterm.kernels[kernel].virt_extmarks[oloc] = {}
  end
end

--- Hides virtual text at a row (keeps sign, removes virt_lines).
---@param kernel string
---@param row? integer
function display.hide_virt_text_at_row(kernel, row)
  row = row or vim.api.nvim_win_get_cursor(0)[1] - 1
  for _, oe in ipairs(vim.api.nvim_buf_get_extmarks(0, Jupyterm.ns_virt, { row, 0 }, { row, 0 }, { details = true })) do
    local oloc = Jupyterm.kernels[kernel].virt_olocs[oe[1]]
    for _, e_id in ipairs(Jupyterm.kernels[kernel].virt_extmarks[oloc] or {}) do
      local e = vim.api.nvim_buf_get_extmark_by_id(0, Jupyterm.ns_virt, e_id, { details = true })
      vim.api.nvim_buf_set_extmark(0, Jupyterm.ns_virt, e[1], e[2], {
        id = e_id,
        sign_text = string.sub(tostring(oloc), -2, -1),
        sign_hl_group = e[3].sign_hl_group,
        hl_group = e[3].hl_group,
        invalidate = true, undo_restore = false,
      })
    end
  end
end

--- Shows virtual text at a row (or cursor row).
---@param kernel string
---@param row? integer
function display.show_virt_text_at_row(kernel, row)
  row = row or vim.api.nvim_win_get_cursor(0)[1] - 1
  for oloc = vim.fn.JupyOutputLen(tostring(kernel)), 1, -1 do
    local vt = Jupyterm.kernels[kernel].virt_text[oloc]
    if vt and row >= vt.start_row and row <= vt.end_row then
      display.show_virt_text(kernel, oloc, vt.start_row, vt.end_row, vt.start_col, vt.end_col, vt.hl)
      return
    end
  end
end

--- Formats output text into virt_lines table.
---@param text string
---@param hl string
---@return table?
function display.split_virt_text(text, hl)
  local result = {}
  for _, line in ipairs(utils.split_by_newlines(text)) do
    table.insert(result, { { line, hl } })
  end
  if #result == 1 and result[1][1][1] == "" then return nil end
  return result
end

--- Expands virtual text into a popup.
---@param kernel? string
---@param row? integer
function display.expand_virt_text(kernel, row)
  kernel = utils.get_kernel(kernel)
  row = row or vim.api.nvim_win_get_cursor(0)[1] - 1

  local buf     = Jupyterm.kernels[kernel].virt_buf
  local extmark = vim.api.nvim_buf_get_extmarks(buf, Jupyterm.ns_virt, { row, 0 }, { row, -1 }, { details = true })[1]
  local oloc    = Jupyterm.kernels[kernel].virt_olocs[extmark[1]]
  local output  = vim.fn.JupyOutput(tostring(kernel))[2][oloc]

  local popup = Popup({
    anchor = "NW", relative = "cursor", position = { row = 0, col = 0 },
    size = { width = "100%", height = "25%" },
    enter = true, focusable = true,
    buf_options = { buftype = "nofile", bufhidden = "hide", swapfile = false,
                    filetype = "jupyterm-" .. Jupyterm.kernels[kernel].kernel_name },
    win_options = { winhighlight = "FloatBorder:" .. extmark[4].sign_hl_group },
    border = { style = "double" },
  })
  popup:mount()
  popup:on("BufLeave", function() popup:unmount() end, { once = true })
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, utils.split_by_newlines(output))
end

return display
