local utils = require("jupyterm.utils")
local display = require("jupyterm.display")
local manage_kernels = require("jupyterm.manage_kernels")
local execute = require("jupyterm.execute")
local menu = require("jupyterm.menu")

---@tag Jupyterm.config
---@signature Jupyterm.config
---
---@class config
---@field default_kernel string
---@field focus_on_show boolean
---@field show_on_send boolean
---@field focus_on_send boolean
---@field inline_display boolean
---@field output_refresh table
---@field ui table
---
---@text Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
--minidoc_replace_start Jupyterm.config = {
local config = {
  --minidoc_replace_end
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
    wait_str = "Computing...",
    queue_str = "Queued",
    repl = {
      format = "split",
      config = {
        relative = "editor",
        position = "right",
        size = "40%",
        enter = false
      },
      keymaps = {
        {"n", "<cr>", execute.send_display_block, "Send display block"},
        {"n", "[c", display.jump_display_block_up, "Jump up one display block"},
        {"n", "]c", display.jump_display_block_down, "Jump down one display block"},
        {"n", "<esc>", display.update_repl, "Refresh"},
        {"n", "<c-c>", manage_kernels.interrupt_kernel, "Interrupt"},
        {"n", "<c-q>", manage_kernels.shutdown_kernel, "Shutdown"},
        {"n", "?", display.show_repl_help, "Help"},
      }
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
--minidoc_afterlines_end

return config
