local Split = require("nui.split")
local Popup = require("nui.popup")
local NuiLine = require("nui.line")
local NuiText = require("nui.text")

local utils = require("jupyterm.utils")
local manage_kernels = require("jupyterm.manage_kernels")

local display = {}

function display.refresh_windows()
  for k,_ in pairs(Jupyterm.kernels) do
    if display.is_showing(k) then
      -- Only refresh if not edited
      if not Jupyterm.kernels[k].edited then
        display.show_output_buf(k, false, Jupyterm.kernels[k].full)
      end
    end
  end
end

function display.refresh_virt_text()
  for k,_ in pairs(Jupyterm.kernels) do
    if display.is_showing_virt_text(k) then
      display.update_all_virt_text(k)
    end
  end
end

function display.get_display_block_top(cur_line, ns_id)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, {0,0}, {cur_line-1,0}, {details=true, overlap=true})
  if #extmarks > 0 then
    return extmarks[#extmarks]
  end
end

function display.get_display_block_bottom(cur_line, ns_id)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, {cur_line,0}, {-1,0}, {details=true, overlap=true})
  if #extmarks > 0 then
    return extmarks[1]
  end
end

function display.is_showing(kernel)
  if Jupyterm.kernels[kernel].show_win then
    if Jupyterm.kernels[kernel].show_win.winid then
      return true
    else
      return false
    end
  else
    return false
  end
end

function display.is_showing_virt_text(kernel)
  if Jupyterm.kernels[kernel].virt_buf then
    local extmarks = vim.api.nvim_buf_get_extmarks(
      Jupyterm.kernels[kernel].virt_buf,
      Jupyterm.ns_virt,
      0,
      -1,
      {details = true}
    )
    if #extmarks > 0 then
      return true
    else
      return false
    end
  else
    return false
  end
end

function display.toggle_output_buf(kernel)
  -- Use buffer id as default
  kernel = kernel or utils.get_kernel_buf_or_buf()

  -- Auto start if not started
  if not Jupyterm.kernels[kernel] then
    local ft = vim.bo.filetype
    local kernel_name = Jupyterm.lang_to_kernel[ft] or Jupyterm.lang_to_kernel["python"]
    manage_kernels.start_kernel(nil, nil, kernel_name)
  end

  if display.is_showing(kernel) then
    display.hide_output_buf(kernel)
  else
    display.show_output_buf(kernel)
  end
end

function display.hide_output_buf(kernel)
  -- Use buffer id as default
  kernel = kernel or utils.get_kernel_buf_or_buf()

  if Jupyterm.kernels[kernel] then
    Jupyterm.kernels[kernel].show_win:hide()
  end
end

function display.show_output_buf(kernel, focus, full)
  if focus == nil then
    focus = Jupyterm.config.focus_on_show
  end
  -- Refresh current window if output window
  kernel = kernel or utils.get_kernel_buf_or_buf()

  -- Track previous location if showing
  local kernel_win = nil
  local win_view = nil
  if display.is_showing(kernel) then
    kernel_win = Jupyterm.kernels[kernel].show_win.winid
    win_view = vim.api.nvim_win_call(kernel_win, vim.fn.winsaveview)
  end

  -- Check if window already exists
  local show_buf = Jupyterm.kernels[kernel].show_buf
  local show_win = Jupyterm.kernels[kernel].show_win
  if show_buf == nil then
    Jupyterm.kernels[kernel].show_buf = vim.api.nvim_create_buf(false, true)
    show_buf = Jupyterm.kernels[kernel].show_buf
    local kernel_name = Jupyterm.kernels[kernel].kernel_name
    utils.rename_buffer(show_buf, "jupyterm:"..kernel_name..":"..kernel)
    vim.api.nvim_set_option_value("filetype", "jupyterm-"..kernel_name, {buf = show_buf})
  else
    vim.api.nvim_buf_set_lines(show_buf, 0, -1, false, {})
  end
  if show_win == nil then
    if Jupyterm.config.ui.format == "split" then
      Jupyterm.kernels[kernel].show_win = Split(Jupyterm.config.ui.config)
    else
      Jupyterm.kernels[kernel].show_win = Popup(Jupyterm.config.ui.config)
    end
    Jupyterm.kernels[kernel].show_win.bufnr = show_buf
    Jupyterm.kernels[kernel].show_win:mount()
    show_win = Jupyterm.kernels[kernel].show_win
  else
    Jupyterm.kernels[kernel].show_win.bufnr = show_buf
    Jupyterm.kernels[kernel].show_win:mount()
    Jupyterm.kernels[kernel].show_win:show()
  end

  -- Get and display inputs/outputs
  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local input = kernel_lines[1]
  local output = kernel_lines[2]

  -- Display empty display_block
  local bufnr = Jupyterm.kernels[kernel].show_win.bufnr
  local commentstring = Jupyterm.jupystring[bufnr]
  local final_txt = NuiLine()
  final_txt:append(
    NuiText(
          string.format(commentstring.." In [%s]: ", #input+1),
          {
            hl_group="JupytermInText",
            hl_mode = "combine",
            hl_eol = true,
            virt_lines_above = true,
            virt_lines = {
              {{
                "───────────────────────────────────────────────────────────────",
                "JupytermInText"
              }},
            }
          }
    ),
    {}
  )
  vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {"",""})
  final_txt:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_in, 2)

  -- Display previous display_blocks
  for ind = #input, 1, -1 do

    -- Check for long display
    local buf_count = vim.api.nvim_buf_line_count(show_buf)
    if full then
      Jupyterm.kernels[kernel].full = true
    else
      Jupyterm.kernels[kernel].full = false
      if buf_count > Jupyterm.config.ui.max_displayed_lines then
        break
      end
    end
    local i = input[ind]
    local o = output[ind]

    -- Display outputs
    local out_txt = NuiLine()
    out_txt:append(
      NuiText(
        string.format(commentstring.." Out [%s]:", ind),
        {
          hl_group="JupytermOutText",
          hl_mode = "combine",
          hl_eol = true,
          virt_lines_above = true,
          virt_lines = {
            {{
              "───────────────────────────────",
              "JupytermOutText"
            }},
          }
        }
      ), {}
    )
    local out_txt2 = NuiLine()
    out_txt2:append(
      NuiText(
        commentstring,
        {
          hl_group="JupytermOutText",
          hl_mode = "combine",
        }
      ), {}
    )
    local split_o = utils.split_by_newlines(o)
    if #split_o > Jupyterm.config.ui.max_displayed_lines then
      split_o = {unpack(split_o, #split_o-Jupyterm.config.ui.max_displayed_lines+1, #split_o)}
    end
    if (#split_o ~= 1) or (utils.strip(split_o[1]) ~= "") then
      vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {""})
      out_txt2:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_out, 2)
      vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, split_o)
      vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {""})
      out_txt:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_out, 2)
    end

    -- Display inputs
    local split_i = utils.split_by_newlines(i)
    local in_txt = NuiLine()
    in_txt:append(
      NuiText(
            string.format(commentstring.." In [%s]: ", ind),
            {
              hl_group="JupytermInText",
              hl_mode = "combine",
              hl_eol = true,
              virt_lines_above = true,
              virt_lines = {
                {{
                  "───────────────────────────────────────────────────────────────",
                  "JupytermInText"
                }},
              }
            }
      ),
      {}
    )
    local in_txt2 = NuiLine()
    in_txt2:append(
      NuiText(
        commentstring,
        {
          hl_group="JupytermInText",
          hl_mode = "combine",
        }
      ), {}
    )
    vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {""})
    in_txt2:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_in, 2)
    vim.api.nvim_buf_set_lines(show_buf, 1, 1, false, split_i)
    vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, 1, 1, false, {""})
    in_txt:render(show_buf, Jupyterm.ns_in, 2)
  end

  -- Navigate to end
  if focus then
    display.navigate_to_output_end(kernel)
  elseif kernel_win and win_view then
    vim.api.nvim_win_call(kernel_win, function() vim.fn.winrestview(win_view) end)
  end

  -- Reset edited status
  Jupyterm.kernels[kernel].edited = nil
end

function display.toggle_virt_text(kernel)
  -- Use buffer id as default
  kernel = kernel or utils.get_kernel_buf_or_buf()

  -- Auto start if not started
  if not Jupyterm.kernels[kernel] then
    local ft = vim.bo.filetype
    local kernel_name = Jupyterm.lang_to_kernel[ft] or Jupyterm.lang_to_kernel["python"]
    manage_kernels.start_kernel(nil, nil, kernel_name)
  end

  if display.is_showing_virt_text(kernel) then
    display.hide_all_virt_text(kernel)
  else
    display.show_all_virt_text(kernel)
  end
end

function display.show_all_virt_text(kernel)
  for oloc=1,vim.fn.JupyOutputLen(tostring(kernel)) do
    local vt = Jupyterm.kernels[kernel].virt_text[oloc]
    display.show_virt_text(kernel, oloc, vt.start_row, vt.end_row, vt.start_col, vt.end_col, vt.hl)
  end
end

function display.hide_all_virt_text(kernel)
  vim.api.nvim_buf_clear_namespace(
    Jupyterm.kernels[kernel].virt_buf,
    Jupyterm.ns_virt,
    0,
    -1
  )
end

function display.update_all_virt_text(kernel)
  local buf = Jupyterm.kernels[kernel].virt_buf
  local olocs = Jupyterm.kernels[kernel].virt_olocs
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, Jupyterm.ns_virt, 0, -1, {details = true})
  local outputs = vim.fn.JupyOutput(tostring(kernel))[2]
  for _,e in ipairs(extmarks) do
    local oloc = olocs[e[1]]
    local formatted_output = display.split_virt_text(outputs[oloc])
    if e[#e].virt_lines then
      vim.api.nvim_buf_set_extmark(buf, Jupyterm.ns_virt, e[2], e[3], {
        id = e[1],
        end_row = e[#e].end_row,
        end_col = e[#e].end_col,
        virt_lines = formatted_output,
        sign_text = e[#e].sign_text,
        sign_hl_group = "JupytermOutText",
        hl_group = e[#e].hl_group,
      })
    else
      vim.api.nvim_buf_set_extmark(buf, Jupyterm.ns_virt, e[2], e[3], {
        id = e[1],
        sign_text = e[#e].sign_text,
        sign_hl_group = "JupytermOutText",
        hl_group = e[#e].hl_group,
      })
    end
  end
end

function display.show_virt_text(kernel, output_num, start_row, end_row, start_col, end_col, hl)
  -- Delete previous extmarks in range
  display.hide_virt_text(kernel, start_row, end_row)

  -- Insert new extmarks
  local kernel_lines = vim.fn.JupyOutput(tostring(kernel))
  local output = kernel_lines[2]
  local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row+1, false)[1]
  local line_len = string.len(end_line)
  output_num = output_num or #output

  for row=start_row,end_row do
    local virt_id = nil
    if row == end_row then
      local formatted_output = display.split_virt_text(output[output_num])
      start_col = start_col or 0
      end_col = end_col or line_len
      virt_id = vim.api.nvim_buf_set_extmark(0, Jupyterm.ns_virt, row, start_col, {
        end_col = end_col,
        virt_lines = formatted_output,
        sign_text = string.sub(tostring(output_num), -2, -1),
        sign_hl_group = "JupytermOutText",
        hl_group = hl,
      })
    else
      virt_id = vim.api.nvim_buf_set_extmark(0, Jupyterm.ns_virt, row, 0, {
        sign_text = string.sub(tostring(output_num), -2, -1),
        sign_hl_group = "JupytermOutText",
        hl_group = hl,
      })
    end
    if Jupyterm.kernels[kernel].virt_olocs == nil then
      Jupyterm.kernels[kernel].virt_olocs = {}
    end
    Jupyterm.kernels[kernel].virt_olocs[virt_id] = output_num
  end
  Jupyterm.kernels[kernel].virt_buf = vim.api.nvim_get_current_buf()
end

function display.hide_virt_text(kernel, start_row, end_row)
  start_row = start_row or vim.api.nvim_win_get_cursor(0)[1] - 1
  end_row = end_row or start_row

  -- Delete extmarks in range
  local overlap_extmarks = vim.api.nvim_buf_get_extmarks(0, Jupyterm.ns_virt, {start_row,0}, {end_row,0}, {details = true})
  local extmarks = vim.api.nvim_buf_get_extmarks(0, Jupyterm.ns_virt, 0, -1, {})
  for _,oe in ipairs(overlap_extmarks) do
    if Jupyterm.kernels[kernel].virt_olocs == nil then
      Jupyterm.kernels[kernel].virt_olocs = {}
    end
    local oloc = Jupyterm.kernels[kernel].virt_olocs[oe[1]]
    for _,e in ipairs(extmarks) do
      if Jupyterm.kernels[kernel].virt_olocs[e[1]] == oloc then
        vim.api.nvim_buf_del_extmark(0, Jupyterm.ns_virt, e[1])
        Jupyterm.kernels[kernel].virt_olocs[e[1]] = nil
      end
    end
  end
end

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

function display.split_virt_text(text)
  local split_text = utils.split_by_newlines(text)
  local result = {}
  for _,st in ipairs(split_text) do
    table.insert(result, {{st, "JupytermVirtText"}})
  end
  return result
end

function display.expand_virt_text(kernel, row)
  kernel = kernel or Jupyterm.send_memory[vim.api.nvim_get_current_buf()]
  row = row or vim.api.nvim_win_get_cursor(0)[1]-1
  local buf = Jupyterm.kernels[kernel].virt_buf
  local extmark = vim.api.nvim_buf_get_extmarks(buf, Jupyterm.ns_virt, {row,0}, {row,-1}, {details = true})[1]
  local outputs = vim.fn.JupyOutput(tostring(kernel))[2]
  local text = extmark[#extmark].virt_lines
  local split_text = {}
  for _,t in ipairs(text) do
    table.insert(split_text, t[1])
  end
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
      filetype = "jupyterm-python3"
    },
    border = "solid"
  })
  popup:mount()
  popup:on("BufLeave", function()
    popup:unmount()
  end, {once = true})
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, split_text)
end

function display.navigate_to_output_end(kernel)
  local winid = Jupyterm.kernels[kernel].show_win.winid
  local buf_len = vim.api.nvim_buf_line_count(Jupyterm.kernels[kernel].show_buf)
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {buf_len, 0})
end

function display.scroll_output_to_bottom(kernel)
  local cur_win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(cur_win)
  display.navigate_to_output_end(kernel)
  vim.api.nvim_set_current_win(cur_win)
  vim.api.nvim_win_set_cursor(cur_win, cursor)
end

function display.jump_display_block_up(kernel)
  kernel = kernel or utils.get_kernel_buf_or_buf()
  local cursor = vim.api.nvim_win_get_cursor(Jupyterm.kernels[kernel].show_win.winid)
  local top_in = display.get_display_block_top(cursor[1], Jupyterm.ns_in)
  local top_out = display.get_display_block_top(cursor[1], Jupyterm.ns_out)
  if top_in then
    -- Check if in "out" or "in" block
    if top_out and top_in[2] < top_out[2] then
      vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {top_in[2]+2, 0})
    else
      -- Extra jump if in "in" block
      top_in = display.get_display_block_top(top_in[2], Jupyterm.ns_in)
      local top_loc = top_in[2]
      if top_in[2] == 0 then
        top_loc = top_loc+3
      else
        top_loc = top_loc+2
      end
      vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {top_loc, 0})
    end
  end
end

function display.jump_display_block_down(kernel)
  kernel = kernel or utils.get_kernel_buf_or_buf()
  local cursor = vim.api.nvim_win_get_cursor(Jupyterm.kernels[kernel].show_win.winid)
  local bottom_in = display.get_display_block_bottom(cursor[1], Jupyterm.ns_in)
  local bottom_out = display.get_display_block_bottom(cursor[1], Jupyterm.ns_out)
  if bottom_in then
    -- Check if in "out" or "in" block
    if bottom_out and bottom_in[2] < bottom_out[2] then
      vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {bottom_in[2]+2, 0})
    else
      -- Extra jump if in "in" block
      bottom_in = display.get_display_block_bottom(bottom_in[2], Jupyterm.ns_in)
      vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {bottom_in[2]+2, 0})
    end
  end
end

return display
