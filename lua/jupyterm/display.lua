---@tag Jupyterm.display
---@signature Jupyterm.display
local Split = require("nui.split")
local Popup = require("nui.popup")
local Line = require("nui.line")
local Text = require("nui.text")

local utils = require("jupyterm.utils")
local manage_kernels = require("jupyterm.manage_kernels")

local display = {}

--- Refreshes all repl windows.
function display.refresh_windows()
  for k,_ in pairs(Jupyterm.kernels) do
    if utils.is_repl_showing(k) then
      -- Only refresh if not edited
      if not Jupyterm.kernels[k].edited then
        display.update_repl(k)
      end
    end
  end
end

--- Refreshes all virtual text.
function display.refresh_virt_text()
  for k,_ in pairs(Jupyterm.kernels) do
    if utils.is_virt_text_showing(k) then
      display.update_all_virt_text(k)
    end
  end
end

--- Toggles the repl buffer.
---@param kernel string?
---@param focus boolean? whether to focus the repl window
---@param full boolean? whether to display the full output
function display.toggle_repl(kernel, focus, full)
  -- Use buffer id as default
  kernel = utils.get_kernel(kernel)

  -- Auto start if not started
  if not Jupyterm.kernels[kernel] then
    local ft = vim.bo.filetype
    local kernel_name = Jupyterm.lang_to_kernel[ft] or Jupyterm.lang_to_kernel["python"]
    manage_kernels.start_kernel(nil, nil, kernel_name)
  end

  if utils.is_repl_showing(kernel) then
    display.hide_repl(kernel)
  else
    display.show_repl(kernel, focus, full)
  end
end

--- Hides the repl buffer.
---@param kernel string?
function display.hide_repl(kernel)
  -- Use buffer id as default
  kernel = utils.get_kernel(kernel)

  if Jupyterm.kernels[kernel] then
    Jupyterm.kernels[kernel].show_win:hide()
  end
end

function display.display_end_block(kernel, input)
  local bufnr = Jupyterm.kernels[kernel].show_win.bufnr
  local commentstring = Jupyterm.jupystring[bufnr]
  local final_txt,_ = display.generate_cell(commentstring, #input+1, "In")
  vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {"",""})
  final_txt:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_in_top, 2)
end

--- Shows the repl buffer.
---@param kernel string?
---@param focus boolean? whether to focus the repl window
---@param full boolean? whether to display the full output
function display.show_repl(kernel, focus, full)
  if focus == nil then
    focus = Jupyterm.config.focus_on_show
  end
  -- Refresh current window if repl window
  kernel = utils.get_kernel(kernel)

  -- Track previous location if showing
  local kernel_win = nil
  local win_view = nil
  if utils.is_repl_showing(kernel) then
    kernel_win = Jupyterm.kernels[kernel].show_win.winid
    win_view = vim.api.nvim_win_call(kernel_win, vim.fn.winsaveview)
  end

  -- Check if window already exists
  local show_buf = Jupyterm.kernels[kernel].show_buf
  local show_win = Jupyterm.kernels[kernel].show_win
  if show_buf then
    vim.api.nvim_buf_set_lines(show_buf, 0, -1, false, {})
    -- Remove hanging cell extmarks
    vim.api.nvim_buf_clear_namespace(show_buf, Jupyterm.ns_in_top, 0, -1)
    vim.api.nvim_buf_clear_namespace(show_buf, Jupyterm.ns_out_top, 0, -1)
  else
    Jupyterm.kernels[kernel].show_buf = vim.api.nvim_create_buf(false, true)
    show_buf = Jupyterm.kernels[kernel].show_buf
    local kernel_name = Jupyterm.kernels[kernel].kernel_name
    utils.rename_buffer(show_buf, "jupyterm:"..kernel_name..":"..kernel)
    vim.api.nvim_set_option_value("filetype", "jupyterm-repl-"..kernel_name, {buf = show_buf})
  end
  if show_win then
    Jupyterm.kernels[kernel].show_win.bufnr = show_buf
    Jupyterm.kernels[kernel].show_win:mount()
    Jupyterm.kernels[kernel].show_win:show()
  else
    if Jupyterm.config.ui.repl.format == "split" then
      Jupyterm.kernels[kernel].show_win = Split(Jupyterm.config.ui.repl.config)
    else
      Jupyterm.kernels[kernel].show_win = Popup(Jupyterm.config.ui.repl.config)
    end
    Jupyterm.kernels[kernel].show_win.bufnr = show_buf
    Jupyterm.kernels[kernel].show_win:mount()
    show_win = Jupyterm.kernels[kernel].show_win
  end

  -- Get and display inputs/outputs
  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local input = kernel_lines[1]
  local output = kernel_lines[2]

  -- Display empty display_block
  display.display_end_block(kernel, input)

  -- Display previous display_blocks
  local bufnr = Jupyterm.kernels[kernel].show_win.bufnr
  local commentstring = Jupyterm.jupystring[bufnr]
  for ind = #input, 1, -1 do

    -- Check for long display
    local buf_count = vim.api.nvim_buf_line_count(show_buf)
    if full then
      Jupyterm.kernels[kernel].show_full_output = true
    else
      Jupyterm.kernels[kernel].show_full_output = false
      if buf_count > Jupyterm.config.ui.max_displayed_lines then
        break
      end
    end
    local i = input[ind]
    local o = output[ind]

    -- Display outputs
    local out_txt, out_txt2 = display.generate_cell(commentstring, ind, "Out")
    local split_o = utils.split_by_newlines(o)
    if #split_o > Jupyterm.config.ui.max_displayed_lines then
      split_o = {unpack(split_o, #split_o-Jupyterm.config.ui.max_displayed_lines+1, #split_o)}
    end
    if (#split_o ~= 1) or (utils.strip(split_o[1]) ~= "") then
      vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {""})
      out_txt2:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_out_bottom, 2)
      vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, split_o)
      vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {""})
      out_txt:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_out_top, 2)
    end

    -- Display inputs
    local split_i = utils.split_by_newlines(i)
    local in_txt, in_txt2 = display.generate_cell(commentstring, ind, "In")
    vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {""})
    in_txt2:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_in_bottom, 2)
    vim.api.nvim_buf_set_lines(show_buf, 1, 1, false, split_i)
    vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {""})
    in_txt:render(show_buf, Jupyterm.ns_in_top, 2)
  end

  -- Navigate to end
  if focus then
    display.navigate_to_repl_end(kernel)
  elseif kernel_win and win_view then
    vim.api.nvim_win_call(kernel_win, function() vim.fn.winrestview(win_view) end)
  end

  -- Reset edited status
  Jupyterm.kernels[kernel].edited = nil
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
        hl_group="Jupyterm"..type.."Text",
        hl_mode = "combine",
        hl_eol = true,
        virt_lines_above = true,
        virt_lines = {
          {{
            "───────────────────────────────────────────────────────────────",
            "Jupyterm"..type.."Text"
          }},
          {{
            string.format(type.." [%s]: ", index),
            "Jupyterm"..type.."Text"
          }},
        }
      }
    ), {}
  )
  local line2 = Line()
  line2:append(
    Text(
      "```",
      {
        hl_group="Jupyterm"..type.."Text",
        hl_mode = "combine",
      }
    ), {}
  )
  return line1, line2
end

--- Updates the repl buffer.
---@param kernel string?
function display.update_repl(kernel)
  kernel = utils.get_kernel(kernel)

  local show_buf = Jupyterm.kernels[kernel].show_buf
  if not show_buf then
    return
  end

  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local inputs = kernel_lines[1]
  local outputs = kernel_lines[2]

  -- Get the extmarks in the buffer
  local in_top_marks = vim.api.nvim_buf_get_extmarks(show_buf, Jupyterm.ns_in_top, 0, -1, {details = true})

  -- Iterate through the extmarks in reverse order and update the buffer if necessary
  for i = #in_top_marks-1, 1, -1 do
    local e = in_top_marks[i]
    local extmark_id = e[1]
    local extmark_row = e[2]
    local extmark_col = e[3]
    local extmark_details = e[4]

    -- Check for ghost extmarks
    if extmark_row ~= 0 then
      -- Get the corresponding input or output index
      local in_index = tonumber(string.match(extmark_details.virt_lines[2][1][1], "%d+"))

      -- Check for/update output cell
      local out_top = utils.get_extmark_below(extmark_row, Jupyterm.ns_out_top)
      local out_bottom = utils.get_extmark_below(extmark_row, Jupyterm.ns_out_bottom)
      if out_top and out_bottom then
        local out_index = tonumber(string.match(out_top[4].virt_lines[2][1][1], "%d+"))
        if in_index == out_index then
          local split_output = utils.split_by_newlines(outputs[in_index])
          local previous_output = vim.api.nvim_buf_get_lines(show_buf, out_top[2]+1, out_bottom[2], false)
          if table.concat(split_output, "\n") ~= table.concat(previous_output, "\n") then
            vim.api.nvim_buf_set_lines(show_buf, out_top[2]+1, out_bottom[2], false, split_output)
          elseif (#previous_output == 1) and (utils.strip(previous_output[1]) == "") then
            vim.api.nvim_buf_set_lines(show_buf, out_top[2], out_bottom[2]+1, false, {})
            vim.api.nvim_buf_del_extmark(show_buf, Jupyterm.ns_out_top, out_top[1])
            vim.api.nvim_buf_del_extmark(show_buf, Jupyterm.ns_out_bottom, out_bottom[1])
          end
        end
      end

      -- Update input cell
      local in_bottom = utils.get_extmark_below(extmark_row, Jupyterm.ns_in_bottom)
      if in_bottom then
        local input = inputs[in_index]
        local previous_input = vim.api.nvim_buf_get_lines(show_buf, extmark_row+1, in_bottom[2], false)
        if input ~= table.concat(previous_input, "\n") then
          local split_input = utils.split_by_newlines(input)
          vim.api.nvim_buf_set_lines(show_buf, extmark_row+1, in_bottom[2], false, split_input)
        end
      end
    end
  end
end

--- Toggles a keymap help menu for repl
---@param kernel string?
function display.show_repl_help(kernel)
  kernel = utils.get_kernel(kernel)

  if utils.is_repl_showing(kernel) then
    local bufnr = Jupyterm.kernels[kernel].show_win.bufnr
    local popup_opts = {
      position = {
        row = 2,
        col = 0,
      },
      anchor = "NW",
      relative = "cursor",
      size = {
        width = "50%",
        height = #Jupyterm.config.ui.repl.keymaps,
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
    for i,k in ipairs(Jupyterm.config.ui.repl.keymaps) do
      local h = Line({
        Text(k[4], "Title"),
        Text(": ", "Title"),
        Text(k[2], "SpecialKey")
      })
      h:render(help_menu.bufnr, help_menu.ns_id, i)
    end
    vim.api.nvim_create_autocmd({"ModeChanged", "CursorMoved"}, {
      group = "Jupyterm",
      callback = function()
        help_menu:unmount()
      end,
      once=true,
      buffer=bufnr
    })
    help_menu:mount()
  end
end

--- Toggles virtual text.
---@param kernel string?
function display.toggle_virt_text(kernel)
  -- Use buffer id as default
  kernel = utils.get_kernel(kernel)

  -- Auto start if not started
  if not Jupyterm.kernels[kernel] then
    local ft = vim.bo.filetype
    local kernel_name = Jupyterm.lang_to_kernel[ft] or Jupyterm.lang_to_kernel["python"]
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
  for oloc=1,vim.fn.JupyOutputLen(tostring(kernel)) do
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
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, Jupyterm.ns_virt, 0, -1, {details = true})
  local outputs = vim.fn.JupyOutput(tostring(kernel))[2]
  for _,e in ipairs(extmarks) do
    local oloc = olocs[e[1]]

    -- Update sign text highlighting
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
  -- Delete previous extmarks in range
  display.delete_virt_text(kernel, start_row, end_row)

  -- Insert new extmarks
  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local output = kernel_lines[2]
  local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row+1, false)[1]
  local line_len = string.len(end_line)
  output_num = output_num or #output

  for row=start_row,end_row do
    local virt_id = nil

    -- Update sign text highlighting
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
      Jupyterm.kernels[kernel].virt_extmarks[output_num] = {virt_id}
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
    {row,0},
    {row,0},
    {details = true}
  )

  local lines_showing = false

  if #overlap_extmark > 0 then
    local oe = overlap_extmark[1]
    local oloc = Jupyterm.kernels[kernel].virt_olocs[oe[1]]
    local extmarks = Jupyterm.kernels[kernel].virt_extmarks[oloc]
    for _,e_id in ipairs(extmarks) do
      local e = vim.api.nvim_buf_get_extmark_by_id(0, Jupyterm.ns_virt, e_id, {details=true})
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

  -- Delete extmarks in range
  local overlap_extmarks = vim.api.nvim_buf_get_extmarks(0, Jupyterm.ns_virt, {start_row,0}, {end_row,0}, {details = true})
  for _,oe in ipairs(overlap_extmarks) do
    local oloc = Jupyterm.kernels[kernel].virt_olocs[oe[1]]
    if Jupyterm.kernels[kernel].virt_extmarks[oloc] then
      for _,e_id in ipairs(Jupyterm.kernels[kernel].virt_extmarks[oloc]) do
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

  -- Update extmarks in range
  local overlap_extmarks = vim.api.nvim_buf_get_extmarks(0, Jupyterm.ns_virt, {row,0}, {row,0}, {details = true})
  for _,oe in ipairs(overlap_extmarks) do
    local oloc = Jupyterm.kernels[kernel].virt_olocs[oe[1]]
    local extmarks = Jupyterm.kernels[kernel].virt_extmarks[oloc]
    for _,e_id in ipairs(extmarks) do
      local e = vim.api.nvim_buf_get_extmark_by_id(0, Jupyterm.ns_virt, e_id, {details=true})
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

  for oloc=vim.fn.JupyOutputLen(tostring(kernel)),1,-1 do
    local vt = Jupyterm.kernels[kernel].virt_text[oloc]
    if (row >= vt.start_row) and (row <= vt.end_row) then
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
---@private
  local split_text = utils.split_by_newlines(text)
  local result = {}
  for _,st in ipairs(split_text) do
    table.insert(result, {{st, hl}})
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
  row = row or vim.api.nvim_win_get_cursor(0)[1]-1

  local buf = Jupyterm.kernels[kernel].virt_buf
  local extmark = vim.api.nvim_buf_get_extmarks(buf, Jupyterm.ns_virt, {row,0}, {row,-1}, {details = true})[1]
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
      filetype = "jupyterm-"..kernel_name
    },
    win_options = {
      winhighlight = "FloatBorder:"..extmark[4].sign_hl_group,
    },
    border = {
      style="double"
    }
  })
  popup:mount()
  popup:on("BufLeave", function()
    popup:unmount()
  end, {once = true})
  local split_output = utils.split_by_newlines(output)
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, split_output)
end

--- Navigates to the end of the output.
---@param kernel string
---@private
function display.navigate_to_repl_end(kernel)
  local winid = Jupyterm.kernels[kernel].show_win.winid
  local buf_len = vim.api.nvim_buf_line_count(Jupyterm.kernels[kernel].show_buf)
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {buf_len, 0})
end

--- Scrolls the output to the bottom.
---@param kernel string
function display.scroll_repl_to_bottom(kernel)
  local cur_win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(cur_win)
  display.navigate_to_repl_end(kernel)
  vim.api.nvim_set_current_win(cur_win)
  vim.api.nvim_win_set_cursor(cur_win, cursor)
end

--- Jumps to the previous display block.
---@param kernel string?
function display.jump_display_block_up(kernel)
  kernel = utils.get_kernel(kernel)
  local cur_line = vim.api.nvim_win_get_cursor(Jupyterm.kernels[kernel].show_win.winid)[1]
  local out_above = utils.get_extmark_above(cur_line, Jupyterm.ns_out_top)[2]
  local in_above = utils.get_extmark_above(cur_line, Jupyterm.ns_in_top)[2]
  if out_above and (in_above > out_above) then
    cur_line = in_above-1
  elseif out_above then
    cur_line = out_above
  else
    cur_line = in_above-1
  end
  in_above = utils.get_extmark_above(cur_line, Jupyterm.ns_in_top)[2]
  vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {in_above+2, 0})
end

--- Jumps to the next display block.
---@param kernel string?
function display.jump_display_block_down(kernel)
  kernel = utils.get_kernel(kernel)
  local cur_line = vim.api.nvim_win_get_cursor(Jupyterm.kernels[kernel].show_win.winid)[1]
  local in_below = utils.get_extmark_below(cur_line, Jupyterm.ns_in_top)[2]
  vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {in_below+2, 0})
end

return display
