local config = {
  default_kernel = "python3",
  focus_on_show = true,
  show_on_send = true,
  focus_on_send = false,
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
  }
}

return config
