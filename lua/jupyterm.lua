local Jupyterm = {kernels={}, send_memory={}}

Jupyterm.config = {
  focus_on_show = true,
  focus_on_send = false,
  send_update_delay = 100,
}

local Split = require("nui.split")
local NuiLine = require("nui.line")
local NuiText = require("nui.text")

vim.api.nvim_create_augroup("Jupyterm", {clear = true})
vim.api.nvim_create_autocmd("FileType", {
  group = "Jupyterm",
  pattern = "jupyterm",
  callback = function()
    local status, _ = pcall(require, 'nvim-treesitter')
    if status then
      vim.api.nvim_set_option_value("syntax", "on", {buf = 0})
      vim.treesitter.language.register('python', 'jupyterm')
      vim.cmd[[TSBufEnable highlight]]
    else
      vim.cmd[[runtime! syntax/python.vim]]
    end
    vim.bo.tabstop = 4
    vim.bo.shiftwidth = 4
    vim.bo.expandtab = true
    vim.keymap.set("n", "<cr>", Jupyterm.send_repl_cell, {desc="Send cell", buffer=0})
    vim.keymap.set("n", "[c", Jupyterm.jump_repl_up, {desc="Jump up one cell", buffer=0})
    vim.keymap.set("n", "]c", Jupyterm.jump_repl_down, {desc="Jump down one cell", buffer=0})
    vim.keymap.set("n", "<esc>", function() Jupyterm.show_outputs(nil, true) end, {desc="Refresh", buffer=0})
  end
})

Jupyterm.ns_in = vim.api.nvim_create_namespace("jupyterm-in")
Jupyterm.ns_out = vim.api.nvim_create_namespace("jupyterm-out")
vim.api.nvim_set_hl(0, "JupytermInText", {link = "@markup.heading.2.markdown", default = true})
vim.api.nvim_set_hl(0, "JupytermOutText", {link = "Identifier", default = true})

local function split_by_newlines(input)
    local result = {}
    for line in input:gmatch("([^\n]*)\n?") do
        table.insert(result, line)
    end
    return result
end

local function strip(s)
    return s:match("^%s*(.-)%s*$")
end

function Jupyterm.get_cell_top(cur_line, ns_id)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, {0,0}, {cur_line-1,0}, {details=true, overlap=true})
  if #extmarks > 0 then
    return extmarks[#extmarks]
  end
end

function Jupyterm.get_cell_bottom(cur_line, ns_id)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, {cur_line,0}, {-1,0}, {details=true, overlap=true})
  if #extmarks > 0 then
    return extmarks[1]
  end
end

function Jupyterm.is_jupyterm(buf)
    return vim.api.nvim_get_option_value("filetype", {buf=buf}) == "jupyterm"
end

function Jupyterm.find_kernel(buf)
  for k,v in pairs(Jupyterm.kernels) do
    if v.show_buf and v.show_buf == buf then
      return k
    end
  end
end

function Jupyterm.get_kernel_if_in_kernel_buf()
  if Jupyterm.is_jupyterm(vim.api.nvim_get_current_buf()) then
    return Jupyterm.find_kernel(vim.api.nvim_get_current_buf())
  end
end

function Jupyterm.is_showing(kernel)
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

function Jupyterm.toggle_outputs(kernel)
  -- Use buffer id as default
  local kernel_buf_name = "buf:"..vim.api.nvim_get_current_buf()
  if kernel == nil or kernel == "" then
    kernel = Jupyterm.get_kernel_if_in_kernel_buf() or kernel_buf_name
  end
  if Jupyterm.kernels[kernel] == nil then
    vim.print("No kernel named "..kernel)
    return
  end

  if Jupyterm.is_showing(kernel) then
    Jupyterm.hide_outputs(kernel)
  else
    Jupyterm.show_outputs(kernel)
  end
end

function Jupyterm.hide_outputs(kernel)
  if Jupyterm.kernels[kernel] then
    Jupyterm.kernels[kernel].show_win:hide()
  end
end

function Jupyterm.show_outputs(kernel, focus)
  if focus == nil then
    focus = Jupyterm.config.focus_on_show
  end
  -- Refresh current window if output window
  local cur_win = nil
  local cursor = nil
  if kernel == nil then
    kernel = Jupyterm.get_kernel_if_in_kernel_buf()
    cur_win = vim.api.nvim_get_current_win()
    cursor = vim.api.nvim_win_get_cursor(cur_win)
  end

  -- Check if window already exists
  local show_buf = Jupyterm.kernels[kernel].show_buf
  local show_win = Jupyterm.kernels[kernel].show_win
  if show_buf == nil then
    Jupyterm.kernels[kernel].show_buf = vim.api.nvim_create_buf(false, true)
    show_buf = Jupyterm.kernels[kernel].show_buf
    vim.api.nvim_set_option_value("filetype", "jupyterm", {buf = show_buf})
  else
    vim.api.nvim_buf_set_lines(show_buf, 0, -1, false, {})
  end
  if show_win == nil then
    Jupyterm.kernels[kernel].show_win = Split({
      relative = "editor",
      position = "right",
      size = "40%",
      enter = false
    })
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

  for ind = 1, #input do
    local i = input[ind]
    local o = output[ind]

    -- Display inputs
    local split_i = split_by_newlines(i)
    local in_txt = NuiLine()
    in_txt:append(
      NuiText(
            string.format("In [%s]: ", ind),
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
    local buf_count = vim.api.nvim_buf_line_count(show_buf)
    if buf_count == 1 then
      in_txt:render(show_buf, Jupyterm.ns_in, 2)
    else
      in_txt:render(show_buf, Jupyterm.ns_in, buf_count)
    end
    vim.api.nvim_buf_set_lines(show_buf, -1, -1, false, split_i)

    -- Display outputs
    local out_txt = NuiLine()
    out_txt:append(
      NuiText(
            string.format("Out [%s]: ", ind),
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
      ),
      {}
    )
    local split_o = split_by_newlines(o)
    if strip(split_o[1]) ~= "" then
      vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, -1, -1, false, {""})
      out_txt:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_out, vim.api.nvim_buf_line_count(Jupyterm.kernels[kernel].show_buf))
      vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, -1, -1, false, split_o)
    end
    vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, -1, -1, false, {""})
  end
  local final_txt = NuiLine()
  final_txt:append(
    NuiText(
          string.format("In [%s]: ", #input+1),
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
  local final_loc = vim.api.nvim_buf_line_count(Jupyterm.kernels[kernel].show_buf)
  if final_loc == 1 then
    final_loc = final_loc + 1
  end
  final_txt:render(Jupyterm.kernels[kernel].show_buf, Jupyterm.ns_in, final_loc)
  vim.api.nvim_buf_set_lines(Jupyterm.kernels[kernel].show_buf, -1, -1, false, {""})

  -- Navigate to end
  if focus then
    Jupyterm.jump_to_output_end(kernel)
  elseif cur_win and cursor then
    local buf_len = vim.api.nvim_buf_line_count(Jupyterm.kernels[kernel].show_buf)
    if cursor[1] > buf_len then
      vim.api.nvim_win_set_cursor(cur_win,{buf_len,0})
    else
      vim.api.nvim_win_set_cursor(cur_win,cursor)
    end
  end
end

function Jupyterm.jump_to_output_end(kernel)
  local winid = Jupyterm.kernels[kernel].show_win.winid
  local buf_len = vim.api.nvim_buf_line_count(Jupyterm.kernels[kernel].show_buf)
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {buf_len, 0})
end

function Jupyterm.scroll_to_bottom(kernel)
  local cur_win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(cur_win)
  local target_win = Jupyterm.kernels[kernel].show_win.winid
  vim.api.nvim_set_current_win(target_win)
  vim.cmd('normal! G')
  vim.api.nvim_set_current_win(cur_win)
  vim.api.nvim_win_set_cursor(cur_win, cursor)
end

function Jupyterm.send(kernel, code)
  vim.fn.JupyEval(tostring(kernel), code)

  -- Update window
  if Jupyterm.is_showing(tostring(kernel)) then
    -- Delay a moment to try to allow processing
    local delay = Jupyterm.config.send_update_delay
    local focus = Jupyterm.config.focus_on_send
    vim.defer_fn(function() Jupyterm.show_outputs(tostring(kernel), focus) end, delay)
    vim.defer_fn(function() Jupyterm.scroll_to_bottom(tostring(kernel)) end, delay)
  end
end

function Jupyterm.send_repl_cell(kernel)
  if kernel == nil then
    kernel = Jupyterm.get_kernel_if_in_kernel_buf()
  end
  local cursor = vim.api.nvim_win_get_cursor(Jupyterm.kernels[kernel].show_win.winid)
  local top_in = Jupyterm.get_cell_top(cursor[1], Jupyterm.ns_in)
  local bottom_in = Jupyterm.get_cell_bottom(cursor[1], Jupyterm.ns_in)
  local bottom_out = Jupyterm.get_cell_bottom(cursor[1], Jupyterm.ns_out)
  local top_out = Jupyterm.get_cell_top(cursor[1], Jupyterm.ns_out)
  if top_in then top_in = top_in[2]+1 end
  if bottom_in then bottom_in = bottom_in[2]+1 end
  if bottom_out then bottom_out = bottom_out[2]+1 end
  if top_out then top_out = top_out[2]+1 end

  -- Ensure we don't send Out results
  local bottom = 0
  if top_in and top_out and top_out > top_in then
    return
  end

  -- Check if the last cell
  if bottom_in then
    -- Check if cell has an output
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
    if strip(l) ~= "" then
      table.insert(clean_lines, l.."\n")
    end
  end

  -- Check if empty cell
  if #clean_lines == 0 then
    return
  end

  -- Send lines
  vim.fn.JupyEval(tostring(kernel), unpack(clean_lines))

  -- Refresh
  Jupyterm.show_outputs(kernel)
end

function Jupyterm.jump_repl_up(kernel)
  if kernel == nil then
    kernel = Jupyterm.get_kernel_if_in_kernel_buf()
  end
  local cursor = vim.api.nvim_win_get_cursor(Jupyterm.kernels[kernel].show_win.winid)
  local top_in = Jupyterm.get_cell_top(cursor[1], Jupyterm.ns_in)
  local top_out = Jupyterm.get_cell_top(cursor[1], Jupyterm.ns_out)
  if top_in then
    -- Check if in "out" or "in" block
    if top_out and top_in[2] < top_out[2] then
      vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {top_in[2]+2, 0})
    else
      -- Extra jump if in "in" block
      top_in = Jupyterm.get_cell_top(top_in[2], Jupyterm.ns_in)
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

function Jupyterm.jump_repl_down(kernel)
  if kernel == nil then
    kernel = Jupyterm.get_kernel_if_in_kernel_buf()
  end
  local cursor = vim.api.nvim_win_get_cursor(Jupyterm.kernels[kernel].show_win.winid)
  local bottom_in = Jupyterm.get_cell_bottom(cursor[1], Jupyterm.ns_in)
  local bottom_out = Jupyterm.get_cell_bottom(cursor[1], Jupyterm.ns_out)
  if bottom_in then
    -- Check if in "out" or "in" block
    if bottom_out and bottom_in[2] < bottom_out[2] then
      vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {bottom_in[2]+2, 0})
    else
      -- Extra jump if in "in" block
      bottom_in = Jupyterm.get_cell_bottom(bottom_in[2], Jupyterm.ns_in)
      vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {bottom_in[2]+2, 0})
    end
  end
end

function Jupyterm.start_kernel(kernel)
  if kernel == nil or kernel == "" then
    local buf = vim.api.nvim_get_current_buf()
    kernel = "buf:"..buf
    Jupyterm.send_memory[buf] = kernel
  end
  if Jupyterm.kernels[kernel] then
    vim.print("Kernel "..kernel.." has already been started.")
  else
    vim.fn.JupyStart(kernel)
    Jupyterm.kernels[kernel] = {}
  end
end

function Jupyterm.send_select(kernel, cmd)
  if kernel == nil then
    kernel = Jupyterm.select_send_term()
  else
    Jupyterm.send(kernel, cmd)
  end
end

function Jupyterm.send_line(kernel)
  kernel = Jupyterm.save_kernel_location(kernel)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(0,row-1,row,true)
  line = string.gsub(line[1], "^%s+", "")
  Jupyterm.send_select(kernel, line)
end

function Jupyterm.send_lines(kernel,start_line,end_line)
  kernel = Jupyterm.save_kernel_location(kernel)
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
  Jupyterm.send_select(kernel,combined)
end

function Jupyterm.send_selection(kernel,line,start_col,end_col)
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
  Jupyterm.send_select(kernel,table.concat(text))
end

function Jupyterm.send_visual(kernel)
  kernel = Jupyterm.save_kernel_location(kernel)
  local start_line, start_col = unpack(vim.fn.getpos("v"), 2, 4)
  local end_line, end_col = unpack(vim.fn.getpos("."), 2, 4)
  if (start_line == end_line) and (start_col ~= end_col) then
    Jupyterm.send_selection(kernel,start_line,start_col,end_col)
  else
    if start_line > end_line then
      Jupyterm.send_lines(kernel,end_line,start_line)
    else
      Jupyterm.send_lines(kernel,start_line,end_line)
    end
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
end

function Jupyterm.send_file(kernel)
  kernel = Jupyterm.save_kernel_location(kernel)
  local start_line = 1
  local end_line = vim.api.nvim_buf_line_count(0)
  Jupyterm.send_lines(kernel,start_line,end_line)
end

function Jupyterm.select_kernel()
  local kernel_keys = vim.tbl_keys(Jupyterm.kernels)
  local return_val = 1
  vim.ui.select(kernel_keys, {
    prompt = "Please select an option:",
  }, function(choice)
      return_val = choice
    end
  )
  return return_val
end

function Jupyterm.select_send_term()
  local buf = vim.api.nvim_get_current_buf()
  local new_kernel = Jupyterm.select_kernel()
  Jupyterm.send_memory[buf] = new_kernel
  return new_kernel
end

function Jupyterm.save_kernel_location(kernel)
  if kernel == nil then
    local buf = vim.api.nvim_get_current_buf()
    if Jupyterm.send_memory[buf] then
      return Jupyterm.send_memory[buf]
    else
      return Jupyterm.select_send_term()
    end
  else
    return kernel
  end
end

function Jupyterm.shutdown_kernel(kernel)
  if kernel == nil or kernel == "" then
    local buf = vim.api.nvim_get_current_buf()
    kernel = "buf:"..buf
  end
  Jupyterm.kernels[kernel] = nil
  vim.fn.JupyShutdown(tostring(kernel))
end

vim.api.nvim_create_user_command("JupyStart", function(args) Jupyterm.start_kernel(args.args) end, {nargs="?"})
vim.api.nvim_create_user_command("JupyShutdown", function(args) Jupyterm.shutdown_kernel(args.args) end, {nargs="?"})
vim.api.nvim_create_user_command("JupyToggle", function(args) Jupyterm.toggle_outputs(args.args) end, {nargs="?"})
vim.api.nvim_create_user_command("JupyShow", function(args) Jupyterm.show_outputs(args.args) end, {nargs=1})
vim.api.nvim_create_user_command("JupyHide", function(args) Jupyterm.hide_outputs(args.args) end, {nargs=1})

_G.Jupyterm = Jupyterm
return Jupyterm
