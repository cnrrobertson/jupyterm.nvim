local Layout = require("nui.layout")
local Text = require("nui.text")
local Line = require("nui.line")
local Menu = require("nui.menu")
local Popup = require("nui.popup")
local Input = require("nui.input")
local event = require("nui.utils.autocmd").event

local utils = require("jupyterm.utils")
local display = require("jupyterm.display")
local manage_kernels = require("jupyterm.manage_kernels")

local menu = {}

-------------------------------------------------------------------------------
-- Menu creation
-------------------------------------------------------------------------------
function menu.toggle_menu()
  if menu.menu_layout and menu.menu_layout.winid then
    menu.menu_layout:unmount()
  else
    menu.show_menu()
  end
end

function menu.create_menu(lines, keys, on_submit)
  local kernel_menu = Menu({
      relative = "editor",
      size = "100%",
      position = 0,
      border = {
        style = "rounded",
        text = {
          top = "Jupyter Clients",
          top_align = "center",
          bottom_align = "left",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal",
      }
    }, {
    zindex = 500,
    enter = true,
    lines = lines,
    max_width = 20,
    keymap = keys,
    on_submit = on_submit,
  })
  return kernel_menu
end

function menu.create_help(keys)
  local popup_opts = {
    position = 0,
    relative = "editor",
    size = "100%",
    border = {
      style = "double",
      text = {
        top = "Help",
        top_align = "center",
      },
    },
    zindex = 500,
    enter = false,
    focusable = false,
  }
  local help_opts = vim.deepcopy(popup_opts)
  help_opts.border.text.top = "Help"
  local help_menu = Popup(help_opts)
  local helps = {
      Line({Text("Focus next", "Title")}),
      Line({Text("  "..menu.join_keys(keys.focus_next), "SpecialKey")}),
      Line({Text("Focus previous", "Title")}),
      Line({Text("  "..menu.join_keys(keys.focus_prev), "SpecialKey")}),
      Line({Text("Select", "Title")}),
      Line({Text("  "..menu.join_keys(keys.submit), "SpecialKey")}),
      Line({Text("Close menu", "Title")}),
      Line({Text("  "..menu.join_keys(keys.close), "SpecialKey")}),
  }
  for i,h in ipairs(helps) do
    h:render(help_menu.bufnr, help_menu.ns_id, i)
  end

  local action_opts = vim.deepcopy(popup_opts)
  action_opts.border.text.top = "Actions"
  local action_menu = Popup(action_opts)
  local actions = {
      Line({Text("New terminal", "Title")}),
      Line({Text("  "..menu.join_keys(keys.new), "SpecialKey")}),
      Line({Text("Destroy terminal", "Title")}),
      Line({Text("  "..menu.join_keys(keys.destroy), "SpecialKey")}),
      Line({Text("Toggle terminal visibility", "Title")}),
      Line({Text("  "..menu.join_keys(keys.toggle), "SpecialKey")}),
  }
  for i,a in ipairs(actions) do
    a:render(action_menu.bufnr, action_menu.ns_id, i)
  end

  local hint_opts = vim.deepcopy(popup_opts)
  hint_opts.border.text.top = "Hints"
  local hint_menu = Popup(hint_opts)
  local hints = {
    Line({Text(" * = displayed terminal", "SpecialKey")})
  }
  for i,h in ipairs(hints) do
    h:render(hint_menu.bufnr, hint_menu.ns_id, i)
  end

  return help_menu, action_menu, hint_menu
end

function menu.show_menu(on_submit)
  vim.schedule(function() vim.cmd[[stopinsert]] end)
  vim.cmd[[redraw]]
  on_submit = on_submit or menu.submit
  local lines = {}
  menu.add_kernels(lines)
  local keys = vim.deepcopy(Jupyterm.config.ui.menu.keys)
  local kernel_menu = menu.create_menu(lines,keys,on_submit)
  local help_menu, action_menu, hint_menu = menu.create_help(keys)
  local menu_layout = Layout(Jupyterm.config.ui.menu.opts,
      Layout.Box({
        Layout.Box(kernel_menu, {size = "70%"}),
        Layout.Box({
          Layout.Box(help_menu, {size = {height = 10}}),
          Layout.Box(action_menu, {size = {height = 14}}),
          Layout.Box(hint_menu, {size = {height = 4}}),
      }, {dir="col", size = {width = 30}})
    }, {dir="row", size = "70%"})
  )
  menu_layout:mount()
  menu.set_autocmds(kernel_menu, menu_layout)
  menu.set_mappings(kernel_menu, keys)
  menu.kernel_menu = kernel_menu
  menu.menu_layout = menu_layout
end

function menu.set_mappings(kernel_menu, keys)
  for _,k in ipairs(keys.new) do
    kernel_menu:map("n", k, menu.new_terminal, {noremap=true})
  end
  for _,k in ipairs(keys.destroy) do
    kernel_menu:map("n", k, menu.destroy_terminal, {noremap=true})
  end
  for _,k in ipairs(keys.toggle) do
    kernel_menu:map("n", k, menu.toggle_terminal, {noremap=true})
  end
end

function menu.set_autocmds(kernel_menu,menu_layout)
  -- Close terminal
  kernel_menu:on({event.BufLeave}, function()
    menu_layout:unmount()
  end, {})
end

function menu.join_keys(keys)
  if keys then
    return table.concat(keys, ", ")
  else
    return ""
  end
end

function menu.submit(item)
  if item then
    local was_shown = display.is_showing(item.kernel)
    display.toggle_output_buf(item.kernel)
    if was_shown then menu.show_menu() end
  end
end

function menu.add_kernels(lines)
  local kernels = Jupyterm.kernels
  if utils.dict_length(kernels) > 0 then
    for n,t in pairs(kernels) do
      local buf_name = n
      local pre_str = ""
      if display.is_showing(n) then
        pre_str = "* "
      end
      local display = pre_str..buf_name
      local menu_item = Menu.item(
        display,{kernel=n}
      )
      if menu.in_lines(lines, menu_item) == false then
        lines[#lines+1] = menu_item
      end
    end
  end
end

function menu.join_keys(keys)
  if keys then
    return table.concat(keys, ", ")
  else
    return ""
  end
end

function menu.new_terminal()
  local free_num = 1
  while Jupyterm.kernels[free_num] do
    free_num = free_num + 1
  end
  manage_kernels.start_kernel(free_num)
  menu.toggle_menu()
  menu.toggle_menu()
end

function menu.destroy_terminal()
  local tree = menu.kernel_menu.tree
  local node = tree:get_node()
  if node then
    manage_kernels.shutdown_kernel(node.kernel)
    menu.toggle_menu()
    menu.toggle_menu()
  end
end

function menu.toggle_terminal()
  local tree = menu.kernel_menu.tree
  local node = tree:get_node()
  if node then
    local was_shown = display.is_showing(node.kernel)
    menu.toggle_menu()
    display.toggle_output_buf(node.kernel)
    menu.toggle_menu()
  end
end

function menu.in_lines(lines, item)
  local in_lines = false
  for _,line in ipairs(lines) do
    if line.text == item.text then
      in_lines = true
    end
  end
  return in_lines
end

return menu
