--- *jupyterm* Neovim Jupyter kernel manager
--- *Jupyterm*
---
--- MIT License Copyright (c) 2025 Connor Robertson
---
--- ===========================================================================
---
--- Key features:
--- - Start, interrupt, shutdown, and restart Jupyter kernels effortlessly.
--- - Send code blocks or selections to a selected kernel.
--- - View Jupyter outputs in a multi-pane REPL (output, variables, input) or as virtual text inline with your code.
--- - Supports multiple languages via their respective Jupyter kernels (Python, R, Julia, etc.)
---
--- # Setup ~
---
--- This plugin needs to be setup with |Jupyterm.setup|. It will create a global
--- Lua table `Jupyterm` which contains the `kernels`.
---
--- See |Jupyterm.config| for available config settings.
---
--- # Usage ~
---
---   1. Start a Kernel: Use the command `:Jupyter start <kernel> [<cwd> <kernel_name>]`.  Replace `<kernel>` with a number/name for the kernel. Optionally, choose the working directory of the kernel with `<cwd>` and choose the language kernel with `<kernel_name>` (e.g., `python3`, `ir`, `ijulia`). By default, Neovim's `cwd` and the `python3` kernel are used.
---
---   2. Send Code: `:Jupyter execute <kernel>` will send the current line to the kernel. Visual selection then `:'<,'>Jupyter execute <kernel>` will send the selection to the kernel. Alternatively, send code directly via `:Jupyter execute <kernel> <code>`.  See the `lua` API in the help file for `send_line`, `send_visual`, `send_select`, and `send_file` from `require("jupyterm.execute")` to send the current line, visual selection, to a selected kernel, and the entire current buffer respectively.
---
---   3. Manage Kernels: Use `:Jupyter status`, `:Jupyter interrupt`, `:Jupyter shutdown`, `:Jupyter restart`, and `:Jupyter menu` to check the status, interrupt execution, shutdown a kernel, restart a kernel, or view active kernels in an interactive popup menu.
---
---   4. Output Display: Outputs will appear in a dedicated REPL widget or inline, depending on your configuration (`jupyterm.config.inline_display`). You can also use `:Jupyter toggle_repl` and `:Jupyter toggle_text` to manage the REPL widget and virtual text respectively. Use `:Jupyter toggle_text_here` to toggle individual inline outputs.
---
---   5. REPL Widget: After opening the REPL with `:Jupyter toggle_repl`, a three-pane layout appears:
---      - Output pane (top): Read-only scrollable history of In/Out blocks.
---      - Variables pane (middle, toggleable): Shows IPython variables via `%whos`.
---      - Input pane (bottom): Editable area for typing code. Press Enter in normal mode to submit.
---
---   6. Variables: Use `:Jupyter toggle_variables` or `<C-v>` in any REPL pane to show/hide the variables inspector.
---
--- # User Commands ~
---
--- User commands are shown below. Optional arguments are marked with a `?`:
---
---   Starts a Jupyter kernel.
---   `:Jupyter start kernel cwd? kernel_name?`
---
---   Shuts down a Jupyter kernel.
---   `:Jupyter shutdown kernel`
---
---   Restarts a Jupyter kernel.
---   `:Jupyter restart kernel`
---
---   Checks the status of a Jupyter kernel.
---   `:Jupyter status kernel`
---
---   Interrupts a Jupyter kernel.
---   `:Jupyter interrupt kernel`
---
---   Executes code in a specified kernel.
---   `:Jupyter execute kernel? code?`
---
---   Toggles the Jupyter kernel menu.
---   `:Jupyter menu`
---
---   Toggles the REPL widget for a kernel.
---   `:Jupyter toggle_repl kernel? focus?`
---
---   Toggles the variables pane for a kernel.
---   `:Jupyter toggle_variables kernel?`
---
---   Toggles the display of virtual text outputs for a kernel.
---   `:Jupyter toggle_text kernel?`
---
---   Toggles virtual text output in the range under the cursor.
---   `:Jupyter toggle_text_here kernel row?`
---
---   Shows virtual text output in the range under the cursor in a popup window.
---   `:Jupyter expand_text_here kernel row?`
---
--- # Highlight groups ~
---
--- * `JupytermInText` - Titles of input blocks in output pane
--- * `JupytermOutText` - Titles of output blocks in output pane
--- * `JupytermVirtQueued` - Color of virtual text when queued for execution
--- * `JupytermVirtComputing` - Color of virtual text when currently being executed
--- * `JupytermVirtCompleted` - Color of virtual text when execution completed
--- * `JupytermVirtError` - Color of virtual text when execution errored
-- Plugin definition =======================================================
local config = require("jupyterm.config")
local utils = require("jupyterm.utils")
local display = require("jupyterm.display")
local manage_kernels = require("jupyterm.manage_kernels")
local execute = require("jupyterm.execute")
local menu = require("jupyterm.menu")
local widget = require("jupyterm.widget")

local Jupyterm = {kernels={}, send_memory={}, jupystring={}}

Jupyterm.kernel_to_lang = {
  python3="python",
  ir="r",
  ijulia="julia",
}

Jupyterm.lang_to_kernel = {
  python="python3",
  r="ir",
  julia="ijulia",
}

--- Update config, setup namespaces, highlight groups, user commands, autocmds, and timers
---@param opts table of options to override the default config
function Jupyterm.setup(opts)
  opts = opts or {}

  -- Update config
  Jupyterm.config = vim.tbl_deep_extend("force", config, opts)

  -- Setup filetypes, namespaces, highlight groups
  vim.api.nvim_create_augroup("Jupyterm", {clear = true})
  Jupyterm.ns_virt = vim.api.nvim_create_namespace("jupyterm-virtual")
  Jupyterm.ns_in_top = vim.api.nvim_create_namespace("jupyterm-in-top")
  Jupyterm.ns_in_bottom = vim.api.nvim_create_namespace("jupyterm-in-bottom")
  Jupyterm.ns_out_top = vim.api.nvim_create_namespace("jupyterm-out-top")
  Jupyterm.ns_out_bottom = vim.api.nvim_create_namespace("jupyterm-out-bottom")
  Jupyterm.ns_trunc = vim.api.nvim_create_namespace("jupyterm-trunc")
  vim.api.nvim_set_hl(0, "JupytermInText", {link = "Function", default = true})
  vim.api.nvim_set_hl(0, "JupytermOutText", {link = "Identifier", default = true})
  vim.api.nvim_set_hl(0, "JupytermVirtQueued", {link = "DiffChange", default = true})
  vim.api.nvim_set_hl(0, "JupytermVirtComputing", {link = "DiffText", default = true})
  vim.api.nvim_set_hl(0, "JupytermVirtCompleted", {link = "DiffAdd", default = true})
  vim.api.nvim_set_hl(0, "JupytermVirtError", {link = "DiffDelete", default = true})

  ---Setup user commands
  ---@param args table of strings to complete
  ---@return function that takes a string and returns a table of strings
  local function completion(args)
    return function(subcmd_arg_lead)
      local start_args = {
        "kernel",
        "cwd",
        "kernel_name",
      }
      return vim.iter(start_args)
        :filter(function(install_arg)
            return install_arg:find(subcmd_arg_lead) ~= nil
        end)
        :totable()
    end
  end
  local subcommand_tbl = {
    start = {
      impl = function(args, opts)
        manage_kernels.start_kernel(unpack(args))
      end,
      complete = {"kernel", "cwd", "kernel_name"}
    },
    shutdown = {
      impl = function(args, opts)
        manage_kernels.shutdown_kernel(unpack(args))
      end,
      complete = {"kernel"}
    },
    restart = {
      impl = function(args, opts)
        manage_kernels.restart_kernel(unpack(args))
      end,
      complete = {"kernel"}
    },
    status = {
      impl = function(args, opts)
        manage_kernels.check_kernel_status(unpack(args))
      end,
      complete = {"kernel"}
    },
    interrupt = {
      impl = function(args, opts)
        manage_kernels.interrupt_kernel(unpack(args))
      end,
      complete = {"kernel"}
    },
    execute = {
      impl = function(args, opts)
        if opts.count > -1 then
          execute.send_lines(args[1], opts.line1, opts.line2)
        elseif (opts.count == -1) and #opts.fargs > 2 then
          if args[1] == "select" then
            execute.send_select(nil, table.concat(opts.fargs, "", 3, #opts.fargs))
          else
            execute.send(args[1], table.concat(opts.fargs, "", 3, #opts.fargs))
          end
        else
          if args[1] == "select" then
            local kernel = execute.select_send_term()
            execute.send_line(kernel)
          else
            execute.send_line(args[1])
          end
        end
      end,
      complete = {"kernel", "code"}
    },
    menu = {
      impl = function(args, opts)
        menu.toggle_menu()
      end,
    },
    toggle_repl = {
      impl = function(args, opts)
        widget.toggle(unpack(args))
      end,
      complete = {"kernel"}
    },
    toggle_variables = {
      impl = function(args, opts)
        widget.toggle_variables(unpack(args))
      end,
      complete = {"kernel"}
    },
    toggle_text = {
      impl = function(args, opts)
        display.toggle_virt_text(unpack(args))
      end,
      complete = {"kernel"}
    },
    toggle_text_here = {
      impl = function(args, opts)
        display.toggle_virt_text_at_row(unpack(args))
      end,
      complete = {"kernel", "row"}
    },
    expand_text_here = {
      impl = function(args, opts)
        display.expand_virt_text(unpack(args))
      end,
      complete = {"kernel", "row"}
    }
  }

  ---@param opts table of options including fargs
  local function jupyterm(opts)
    local fargs = opts.fargs
    local subcommand_key = fargs[1]
    local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
    local subcommand = subcommand_tbl[subcommand_key]
    if not subcommand then
      vim.notify("Jupyter: Unknown command: " .. subcommand_key, vim.log.levels.ERROR)
      return
    end
    subcommand.impl(args, opts)
  end
  vim.api.nvim_create_user_command("Jupyter", jupyterm, {
    nargs = "+",
    desc = "Jupyterm: start, destroy, send to, and display info from Jupyter kernels",
    complete = function(arg_lead, cmdline, _)
      local subcmd_key, subcmd_arg_lead = cmdline:match("^['<,'>]*Jupyter[!]*%s(%S+)%s(.*)$")
      if subcmd_key
        and subcmd_arg_lead
        and subcommand_tbl[subcmd_key]
        and subcommand_tbl[subcmd_key].complete
      then
        return completion(subcommand_tbl[subcmd_key].complete)(subcmd_arg_lead)
      end
      if cmdline:match("^['<,'>]*Jupyter[!]*%s+%w*$") then
        local subcommand_keys = vim.tbl_keys(subcommand_tbl)
        return vim.iter(subcommand_keys)
          :filter(function(key)
            return key:find(arg_lead) ~= nil
          end)
          :totable()
      end
    end,
    range = true
  })

  -- Set configs for output buffers (markdown syntax highlighting)
  -- Only applies to output/virt-text buffers, not input or variables panes
  vim.api.nvim_create_autocmd("FileType", {
    group = "Jupyterm",
    pattern = "jupyterm-repl-*",
    callback = function(opts)
      local pattern = opts.match
      local bufnr = vim.api.nvim_get_current_buf()

      -- Identify language
      local buf_name = vim.api.nvim_buf_get_name(bufnr)
      local language = "python"
      for k, v in pairs(Jupyterm.kernel_to_lang) do
        if string.find(buf_name, ":" .. k .. ":") then
          language = v
        end
      end

      Jupyterm.jupystring[bufnr] = "```" .. language

      -- Syntax highlighting
      local has_ts, _ = pcall(require, 'nvim-treesitter')
      if has_ts then
        vim.treesitter.language.register("markdown", pattern)
        pcall(vim.cmd, "TSBufEnable highlight")
      else
        vim.api.nvim_set_option_value("syntax", "on", { buf = bufnr })
        if vim.g.markdown_fenced_languages then
          table.insert(vim.g.markdown_fenced_languages, language)
        else
          vim.g.markdown_fenced_languages = { language }
        end
        vim.cmd("setlocal syntax=markdown")
      end
    end
  })
  -- Also register jupystring for virtual text popup buffers
  vim.api.nvim_create_autocmd("FileType", {
    group = "Jupyterm",
    pattern = "jupyterm-*",
    callback = function(opts)
      local bufnr = vim.api.nvim_get_current_buf()
      -- Skip if already handled by the repl-* autocmd above
      if Jupyterm.jupystring[bufnr] then return end
      -- Skip input/vars buffers
      if opts.match:find("jupyterm%-input") or opts.match:find("jupyterm%-vars") then return end

      local buf_name = vim.api.nvim_buf_get_name(bufnr)
      local language = "python"
      for k, v in pairs(Jupyterm.kernel_to_lang) do
        if string.find(buf_name, ":" .. k .. ":") then
          language = v
        end
      end
      Jupyterm.jupystring[bufnr] = "```" .. language

      local has_ts, _ = pcall(require, 'nvim-treesitter')
      if has_ts then
        vim.treesitter.language.register("markdown", opts.match)
        pcall(vim.cmd, "TSBufEnable highlight")
      else
        vim.api.nvim_set_option_value("syntax", "on", { buf = bufnr })
        if vim.g.markdown_fenced_languages then
          table.insert(vim.g.markdown_fenced_languages, language)
        else
          vim.g.markdown_fenced_languages = { language }
        end
        vim.cmd("setlocal syntax=markdown")
      end
    end
  })

  -- Output pane settings and keymaps
  vim.api.nvim_create_autocmd("FileType", {
    group = "Jupyterm",
    pattern = "jupyterm-repl-*",
    callback = function()
      vim.bo.tabstop = 4
      vim.bo.shiftwidth = 4
      vim.bo.expandtab = true
      -- Output-specific keymaps
      for _,k in ipairs(Jupyterm.config.ui.repl.output_keymaps) do
        vim.keymap.set(k[1], k[2], k[3], {desc=k[4], buffer=0})
      end
      -- Global keymaps
      for _,k in ipairs(Jupyterm.config.ui.repl.global_keymaps) do
        vim.keymap.set(k[1], k[2], k[3], {desc=k[4], buffer=0})
      end
      -- In output pane, insert-mode keys jump to input pane
      for _, key in ipairs({"i", "I", "a", "A", "o", "O"}) do
        vim.keymap.set("n", key, function()
          local kernel = utils.get_kernel_if_in_widget_buf()
          if kernel then
            local w = Jupyterm.kernels[kernel].widget
            if w and w.win_nrs.input and vim.api.nvim_win_is_valid(w.win_nrs.input) then
              vim.api.nvim_set_current_win(w.win_nrs.input)
              vim.cmd("startinsert")
            end
          end
        end, {desc="Jump to input pane", buffer=0})
      end
    end
  })

  -- Input pane keymaps and settings are bound directly in widget.create()
  -- since the input buffer uses the real language filetype (e.g. "python")
  -- for full LSP, completions, indent, and treesitter support.

  -- Variables pane settings and keymaps
  vim.api.nvim_create_autocmd("FileType", {
    group = "Jupyterm",
    pattern = "jupyterm-vars-*",
    callback = function()
      -- Global keymaps only (read-only pane)
      for _,k in ipairs(Jupyterm.config.ui.repl.global_keymaps) do
        vim.keymap.set(k[1], k[2], k[3], {desc=k[4], buffer=0})
      end
      -- Insert-mode keys jump to input pane
      for _, key in ipairs({"i", "I", "a", "A", "o", "O"}) do
        vim.keymap.set("n", key, function()
          local kernel = utils.get_kernel_if_in_widget_buf()
          if kernel then
            local w = Jupyterm.kernels[kernel].widget
            if w and w.win_nrs.input and vim.api.nvim_win_is_valid(w.win_nrs.input) then
              vim.api.nvim_set_current_win(w.win_nrs.input)
              vim.cmd("startinsert")
            end
          end
        end, {desc="Jump to input pane", buffer=0})
      end
    end
  })

  -- Periodically refresh displayed windows and virtual text
  if Jupyterm.config.output_refresh.enabled then
    local refresh_buf_timer = vim.loop.new_timer()
    local delay = Jupyterm.config.output_refresh.delay
    refresh_buf_timer:start(delay, delay, vim.schedule_wrap(display.refresh_windows))
    local refresh_virt_text_timer = vim.loop.new_timer()
    refresh_virt_text_timer:start(delay, delay, vim.schedule_wrap(display.refresh_virt_text))
  end

  -- Apply winfixbuf to all widget windows
  local major = vim.version().major
  local minor = vim.version().minor
  if (major < 1) and (minor > 9) then
    vim.api.nvim_create_autocmd({"BufWinEnter"}, {
      group = "Jupyterm",
      pattern = {"jupyterm:*", "jupyterm-input:*", "jupyterm-vars:*"},
      callback = function()
        vim.o.winfixbuf = true
      end
    })
  end

  -- Ensure virtual text is forgotten when buffer is closed
  vim.api.nvim_create_autocmd({"BufDelete"}, {
    group = "Jupyterm",
    pattern = "*",
    callback = function(opts)
      local bufnr = opts.buf
      for kernel, info in pairs(Jupyterm.kernels) do
        if info.virt_buf == bufnr then
          Jupyterm.kernels[kernel].virt_buf = nil
        end
      end
    end
  })
end

_G.Jupyterm = Jupyterm
return Jupyterm