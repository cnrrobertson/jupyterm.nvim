local Jupyterm = {kernels={}}

local Split = require("nui.split")
local NuiLine = require("nui.line")
local NuiText = require("nui.text")

vim.api.nvim_create_augroup("Jupyterm", {clear = true})
vim.api.nvim_create_autocmd("FileType", {
  group = "Jupyterm",
  pattern = "jupyterm",
  callback = function()
    local status, ts = pcall(require, 'nvim-treesitter')
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
    vim.keymap.set("n", "<esc>", Jupyterm.show_outputs, {desc="Refresh", buffer=0})
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

function Jupyterm.show_outputs(kernel)
  if kernel == nil then
    kernel = Jupyterm.get_kernel_if_in_kernel_buf()
  end
  local show_buf = Jupyterm.kernels[kernel].show_buf
  local show_win = Jupyterm.kernels[kernel].show_win
  if show_buf == nil then
    Jupyterm.kernels[kernel].show_buf = vim.api.nvim_create_buf(false, true)
    show_buf = Jupyterm.kernels[kernel].show_buf
  else
    vim.api.nvim_buf_set_lines(show_buf, 0, -1, false, {})
  end
  if show_win == nil or show_win.winid == nil then
    vim.api.nvim_set_option_value("filetype", "jupyterm", {buf = show_buf})
    Jupyterm.kernels[kernel].show_win = Split({
      relative = "editor",
      position = "right",
      size = "40%",
      enter = false
    })
    Jupyterm.kernels[kernel].show_win.bufnr = show_buf
    Jupyterm.kernels[kernel].show_win:mount()
    show_win = Jupyterm.kernels[kernel].show_win
  end

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
      -- "-- in --",
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
      -- "-- out --",
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
    -- "-- in --",
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
  vim.api.nvim_win_set_cursor(Jupyterm.kernels[kernel].show_win.winid, {vim.api.nvim_buf_line_count(Jupyterm.kernels[kernel].show_buf), 0})
end

function Jupyterm.send(kernel, code)
  vim.fn.JupyEval(tostring(kernel), code)
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
  if Jupyterm.kernels[kernel] then
    vim.print("Kernel "..kernel.." has already been started.")
  else
    vim.fn.JupyStart(kernel)
    Jupyterm.kernels[kernel] = {}
  end
end

vim.api.nvim_create_user_command("JupyStart", function(args) Jupyterm.start_kernel(args.args) end, {nargs=1})
vim.api.nvim_create_user_command("JupyShow", function(args) Jupyterm.show_outputs(args.args) end, {nargs=1})

_G.Jupyterm = Jupyterm
return Jupyterm
