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
--- Keymaps use lazy wrapper functions to avoid circular require issues.
--- The actual modules are resolved at call time, not at require time.
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
      -- Window position: "right", "left", or "bottom"
      position = "right",
      -- Width for right/left position
      width = "40%",
      -- Height for bottom position
      height = "30%",
      -- Fixed height for the input pane
      input_height = 10,
      -- Keymaps for the input pane
      input_keymaps = {
        {"n", "<cr>", function() require("jupyterm.execute").send_input_pane() end, "Run"},
        {"n", "e", function() require("jupyterm.widget").pop_input() end, "Expand in popup"},
        {"n", "[[", function() require("jupyterm.display").history_prev() end, "Prev"},
        {"n", "]]", function() require("jupyterm.display").history_next() end, "Next"},
      },
      -- Keymaps for the output pane
      output_keymaps = {
        {"n", "<cr>", function() require("jupyterm.execute").send_display_block() end, "Run"},
        {"n", "e", function() require("jupyterm.display").yank_block_to_input() end, "Edit"},
        {"n", "[[", function() require("jupyterm.display").jump_display_block_up() end, "Prev"},
        {"n", "]]", function() require("jupyterm.display").jump_display_block_down() end, "Next"},
        {"n", "<esc>", function() require("jupyterm.display").refresh_output() end, "Refresh"},
      },
      -- Keymaps for all panes
      global_keymaps = {
        {"n", "<c-c>", function() require("jupyterm.manage_kernels").interrupt_kernel() end, "Stop"},
        {"n", "<c-q>", function() require("jupyterm.manage_kernels").shutdown_kernel() end, "Quit"},
        {"n", "<c-v>", function() require("jupyterm.widget").toggle_variables() end, "Vars"},
        {"n", "?", function() require("jupyterm.display").show_repl_help() end, "See all"},
      },
      -- Variables pane settings
      variables = {
        -- Allow toggling the variables pane
        enabled = true,
        -- Automatically refresh variables after each execution
        auto_update = true,
        -- Maximum height for the variables pane
        max_height = 15,
        -- IPython magic command to get variables
        command = "%whos",
      },
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