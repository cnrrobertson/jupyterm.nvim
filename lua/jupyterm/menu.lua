---@module nui.layout
local Layout = require("nui.layout")
local Text = require("nui.text")
local Line = require("nui.line")
local Menu = require("nui.menu")
local Popup = require("nui.popup")
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

---Creates a menu with the given lines, keys, and on_submit function.
---@param lines string[] A table of lines to display in the menu.
---@param keys table<string, string> A table of key mappings for the menu.
---@param on_submit fun(table): nil A function to call when an item is submitted.
---@return Menu A nui.Menu object.
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

---Creates a help menu with the given keys.
---@param keys table<string, string> A table of key mappings for the menu.
---@return Popup A nui.Popup object for help, actions, and hints.
---@overload fun(keys: table<string, string>): Popup,Popup,Popup
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
      Line({Text("New kernel", "Title")}),
      Line({Text("  "..menu.join_keys(keys.new), "SpecialKey")}),
      Line({Text("Destroy kernel", "Title")}),
      Line({Text("  "..menu.join_keys(keys.destroy), "SpecialKey")}),
      Line({Text("Toggle kernel REPL", "Title")}),
      Line({Text("  "..menu.join_keys(keys.toggle), "SpecialKey")}),
  }
  for i,a in ipairs(actions) do
    a:render(action_menu.bufnr, action_menu.ns_id, i)
  end

  local hint_opts = vim.deepcopy(popup_opts)
  hint_opts.border.text.top = "Hints"
  local hint_menu = Popup(hint_opts)
  local hints = {
    Line({Text(" * = displayed REPL", "SpecialKey")})
  }
  for i,h in ipairs(hints) do
    h:render(hint_menu.bufnr, hint_menu.ns_id, i)
  end

  return help_menu, action_menu, hint_menu
end

---Shows the Jupyter menu.
---@param on_submit (fun(table): nil)? The function to call when an item is submitted.
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

---Sets the mappings for the given menu.
---@param kernel_menu Menu The nui.Menu object.
---@param keys table<string, string> A table of key mappings.
function menu.set_mappings(kernel_menu, keys)
  for _,k in pairs(keys.new) do
    kernel_menu:map("n", k, menu.new_kernel, {noremap=true})
  end
  for _,k in pairs(keys.destroy) do
    kernel_menu:map("n", k, menu.destroy_kernel, {noremap=true})
  end
  for _,k in pairs(keys.toggle) do
    kernel_menu:map("n", k, menu.toggle_kernel, {noremap=true})
  end
end

---Sets the autocommands for the given menu.
---@param kernel_menu Menu The nui.Menu object.
---@param menu_layout Layout The nui.Layout object.
function menu.set_autocmds(kernel_menu,menu_layout)
  -- Close terminal
  kernel_menu:on({event.BufLeave}, function()
    menu_layout:unmount()
  end, {})
end

---Joins the given keys with commas.
---@param keys string[] A table of keys.
---@return string # A string of keys joined by commas.
function menu.join_keys(keys)
  if keys then
    return table.concat(keys, ", ")
  else
    return ""
  end
end

---Submits the given item.
---@param item table<field, string> The item to submit.
function menu.submit(item)
  if item then
    local was_shown = display.is_repl_showing(item.kernel)
    display.toggle_repl(item.kernel)
    if was_shown then menu.show_menu() end
  end
end

---Adds kernels to the given lines.
---@param lines string[] The table of lines to add kernels to.
function menu.add_kernels(lines)
  local kernels = Jupyterm.kernels
  if utils.table_length(kernels) > 0 then
    for n,t in pairs(kernels) do
      local buf_name = n
      local pre_str = ""
      if display.is_repl_showing(n) then
        pre_str = "* "
      end
      local display_text = pre_str..buf_name
      local menu_item = Menu.item(
        display_text,{kernel=n}
      )
      if menu.in_lines(lines, menu_item) == false then
        lines[#lines+1] = menu_item
      end
    end
  end
end

--- Creates a new kernel.
function menu.new_kernel()
  local free_num = 1
  while Jupyterm.kernels[free_num] do
    free_num = free_num + 1
  end
  manage_kernels.start_kernel(tostring(free_num))
  menu.toggle_menu()
  menu.toggle_menu()
end

--- Destroys the selected kernel.
function menu.destroy_kernel()
  local tree = menu.kernel_menu.tree
  local node = tree:get_node()
  if node then
    manage_kernels.shutdown_kernel(node.kernel)
    menu.toggle_menu()
    menu.toggle_menu()
  end
end

--- Toggles the visibility of the selected kernel.
function menu.toggle_kernel()
  local tree = menu.kernel_menu.tree
  local node = tree:get_node()
  if node then
    menu.toggle_menu()
    display.toggle_repl(node.kernel)
    menu.toggle_menu()
  end
end

---Checks if the given item is in the given lines.
---@param lines string[] The table of lines to check.
---@param item table<string, string> The item to check.
---@return boolean in_lines True if the item is in the lines, false otherwise.
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
