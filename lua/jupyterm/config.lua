---@class config
---@field default_kernel string
---@field focus_on_show boolean
---@field show_on_send boolean
---@field focus_on_send boolean
---@field inline_display boolean
---@field output_refresh table
---@field ui table
local config = {
  -- The default Jupyter kernel to use
  default_kernel = "python3",
  -- Focus the REPL window when showing
  focus_on_show = true,
  -- Show the REPL window when sending text to it
  show_on_send = false,
  -- Focus the REPL window when sending text to it
  focus_on_send = false,
  -- Show outputs inline as virtual text when sending text
  inline_display = true,
  -- Automatic refreshing of REPL window and virtual text
  output_refresh = {
    enabled = true,
    delay = 2000,
  },
  -- UI options for the REPL window and the menu
  ui = {
    format = "split",
    config = {
      relative = "editor",
      position = "right",
      size = "40%",
      enter = false
    },
    max_displayed_lines = 500,
    menu = {
      keys = {
        focus_next = {"j", "<Down>", "<Tab>"},
        focus_prev = {"k", "<Up>", "<S-Tab>"},
        submit = {"<CR>", "<Space>"},
        close = {"<Esc>", "<C-c>", "q"},
        new = {"n"},
        destroy = {"d"},
        toggle = {"w"},
      },
      opts = {
        relative = "editor",
        position = '50%',
        size = '50%',
        zindex = 500
      }
    }
  }
}

return config
