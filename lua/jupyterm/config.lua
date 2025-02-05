---@class config
---@field default_kernel string
---@field focus_on_show boolean
---@field show_on_send boolean
---@field focus_on_send boolean
---@field inline_display boolean
---@field output_refresh table
---@field ui table
local config = {
  default_kernel = "python3",
  focus_on_show = true,
  show_on_send = false,
  focus_on_send = false,
  inline_display = true,
  output_refresh = {
    enabled = true,
    delay = 2000,
  },
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
