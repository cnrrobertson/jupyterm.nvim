local Jupyterm = {}

local Split = require("nui.split")
local NuiLine = require("nui.line")


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
    vim.keymap.set("n", "[", Jupyterm.jump_repl_up, {desc="Jump up one cell", buffer=0})
    vim.keymap.set("n", "]", Jupyterm.jump_repl_down, {desc="Jump down one cell", buffer=0})
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
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, {0,0}, {cur_line,0}, {details=true})
  if #extmarks > 0 then
    return extmarks[#extmarks]
  end
end

function Jupyterm.get_cell_bottom(cur_line, ns_id)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, {cur_line,0}, {-1,0}, {details=true})
  if #extmarks > 0 then
    return extmarks[1]
  end
end

function Jupyterm.show_outputs()
  if Jupyterm.show_buf == nil then
    Jupyterm.show_buf = vim.api.nvim_create_buf(false, true)
  end
  if Jupyterm.show_win == nil or Jupyterm.show_win.winid == nil then
    vim.api.nvim_set_option_value("filetype", "jupyterm", {buf = Jupyterm.show_buf})
    Jupyterm.show_win = Split({
      relative = "editor",
      position = "right",
      size = "40%",
      enter = false
    })
    Jupyterm.show_win.bufnr = Jupyterm.show_buf
    Jupyterm.show_win:mount()
  else
    vim.api.nvim_buf_set_lines(Jupyterm.show_buf, 0, -1, false, {})
  end

  local kernel_lines = vim.fn.JupyOutput()
  local input = kernel_lines[1]
  local output = kernel_lines[2]

  for ind = 1, #input do
    local i = input[ind]
    local o = output[ind]

    -- Display inputs
    local split_i = split_by_newlines(i)
    local in_txt = NuiLine()
    in_txt:append(
      "",
      {
        line_hl_group = "JupytermInText",
        hl_mode = "combine",
        hl_eol = true,
        virt_lines_above = true,
        virt_lines = {
          {{
            "───────────────────────────────────────────────────────────────",
            "JupytermInText"
          }},
          {{
            string.format("In [%s]: ", ind),
            "JupytermInText"
          }}
        }
      }
    )
    local buf_count = vim.api.nvim_buf_line_count(Jupyterm.show_buf)
    if buf_count == 1 then
      in_txt:render(Jupyterm.show_buf, Jupyterm.ns_in, 2)
    else
      in_txt:render(Jupyterm.show_buf, Jupyterm.ns_in, buf_count)
    end
    vim.api.nvim_buf_set_lines(Jupyterm.show_buf, -1, -1, false, split_i)

    -- Display outputs
    local out_txt = NuiLine()
    out_txt:append(
      "",
      {
        line_hl_group = "JupytermOutText",
        hl_mode = "combine",
        hl_eol = true,
        virt_lines_above = true,
        virt_lines = {
          {{
            "───────────────────────────────",
            "JupytermOutText"
          }},
          {{
            string.format("Out [%s]: ", ind),
            "JupytermOutText"
          }}
        }
      }
    )
    local split_o = split_by_newlines(o)
    if strip(split_o[1]) ~= "" then
      vim.api.nvim_buf_set_lines(Jupyterm.show_buf, -1, -1, false, {""})
      out_txt:render(Jupyterm.show_buf, Jupyterm.ns_out, vim.api.nvim_buf_line_count(Jupyterm.show_buf))
      vim.api.nvim_buf_set_lines(Jupyterm.show_buf, -1, -1, false, split_o)
    end
    vim.api.nvim_buf_set_lines(Jupyterm.show_buf, -1, -1, false, {""})
  end
  local final_txt = NuiLine()
  final_txt:append(
    "",
    {
      line_hl_group = "JupytermInText",
      hl_mode = "combine",
      hl_eol = true,
      virt_lines_above = true,
      virt_lines = {
        {{
          "───────────────────────────────────────────────────────────────",
          "JupytermInText"
        }},
        {{
          string.format("In [%s]: ", #input+1),
          "JupytermInText"
        }}
      }
    }
  )
  final_txt:render(Jupyterm.show_buf, Jupyterm.ns_in, vim.api.nvim_buf_line_count(Jupyterm.show_buf))
  vim.api.nvim_buf_set_lines(Jupyterm.show_buf, -1, -1, false, {""})

  -- Navigate to end
  vim.api.nvim_win_set_cursor(Jupyterm.show_win.winid, {vim.api.nvim_buf_line_count(Jupyterm.show_buf), 0})
end

function Jupyterm.send(code)
  vim.fn.JupyEval(code)
end

function Jupyterm.send_repl_cell()
  local cursor = vim.api.nvim_win_get_cursor(Jupyterm.show_win.winid)
  local top = Jupyterm.get_cell_top(cursor[1], Jupyterm.ns_in)
  local bottom_in = Jupyterm.get_cell_bottom(cursor[1], Jupyterm.ns_in)
  local bottom_out = Jupyterm.get_cell_bottom(cursor[1], Jupyterm.ns_out)
  local top_out = Jupyterm.get_cell_top(cursor[1], Jupyterm.ns_out)
  if top then top = top[2] end
  if bottom_in then bottom_in = bottom_in[2] end
  if bottom_out then bottom_out = bottom_out[2] end
  if top_out then top_out = top_out[2] end

  -- Ensure we don't send Out results
  local bottom = 0
  if bottom_in and bottom_out and bottom_in > bottom_out then
    if top_out and top_out > bottom_in then
      bottom = top_out
    else
      bottom = bottom_out
    end
  else
    if bottom_in then
      bottom = bottom_in
    else
      bottom = vim.api.nvim_buf_line_count(Jupyterm.show_buf)
    end
  end

  -- Clean up lines
  local lines = vim.api.nvim_buf_get_lines(Jupyterm.show_buf, top, bottom, false)
  local clean_lines = {}
  for _,l in ipairs(lines) do
    if strip(l) ~= "" then
      table.insert(clean_lines, l.."\n")
    end
  end

  -- Send lines
  vim.fn.JupyEval(unpack(clean_lines))

  -- Refresh
  Jupyterm.show_outputs()
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

vim.api.nvim_create_user_command("JupyShow", Jupyterm.show_outputs, {nargs="*"})

_G.Jupyterm = Jupyterm
return Jupyterm
