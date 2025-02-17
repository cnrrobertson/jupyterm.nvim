--- *jupyterm* Neovim Jupyter kernel manager
--- *Jupyterm*
---
--- MIT License Copyright (c) 2025 Connor Robertson
---
--- ===========================================================================
---
--- Key features:
--- - Start, interrupt, and shutdown Jupyter kernels effortlessly.
--- - Send code blocks or selections to a selected kernel.
--- - View Jupyter outputs in REPL buffers or as virtual text inline with your code.
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
---   3. Manage Kernels: Use `:Jupyter status`, `:Jupyter interrupt`, `:Jupyter shutdown`, and `:Jupyter menu` to check the status, interrupt execution, shutdown a kernel, or view active kernels in an interactive popup menu.
---
---   4. Output Display: Outputs will appear in a dedicated REPL buffer or inline, depending on your configuration (`jupyterm.config.inline_display`). You can also use `:Jupyter toggle_repl` and `:Jupyter toggle_text` to manage the REPL buffer and virtual text respectively. Use `:Jupyter toggle_text_here` to toggle individual inline outputs.
---
---   5. REPL: After opening the REPL buffer with `:Jupyter toggle_repl`, the buffer may be edited as normal. Text inserted below the last `In [*]` in the buffer will be considered a new input. By default, hitting enter in normal mode will submit the input to the kernel. See the [REPL section](#repl) for more information on this buffer.
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
---   Toggles the REPL window for a kernel.
---   `:Jupyter toggle_repl kernel? focus? full?`
---
---   Toggles the display of virtual text outputs for a kernel.
---   `:Jupyter toggle_text kernel?`
---
---   Toggles virtual text output in the range under the cursor.
---   `:Jupyter toggle_text_here kernel row?`
---
--- Note that `kernel` generally refers to the kernel identifier in Neovim and not the `kernel_name` or the actual descriptor of a Jupyter kernel (e.g., `python3`, `ir`). Optional arguments can be omitted.
---
--- # REPL ~
---
--- The REPL (Read-Eval-Print Loop) buffer provides an interactive environment for executing code and viewing results. This buffer can be shown using `:Jupyter toggle_repl`. Text inserted *after* the last `In [*]` marker in this buffer is treated as a new input cell. Pressing Enter in normal mode will submit this input to the kernel.
---
--- The REPL buffer automatically refreshes to display updates from long-running computations. However, this automatic refresh pauses when you begin typing new input, preventing accidental overwriting.
---
--- To manage the length of the buffer and optimize refresh speed, the buffer's display is limited to a certain number of lines (configurable via `jupyterm.config.ui.max_displayed_lines`).  This prevents performance slowdowns from extremely large outputs. If needed, you can view the complete output by using the `full` argument of `Jupyter toggle_repl` or see the `lua` API in the help file.
---
--- The REPL buffer also comes with default keybindings for convenience:
---
---    *<CR>*: Submits the current input to the kernel.
---    *<Esc>*: Refreshes the display, showing the most current kernel output.
---    *[c*: Jumps to the previous display block.
---    *]c*: Jumps to the next display block.
---    *<C-c>*: Interrupts the currently running kernel.
---    *<C-q>*: Shuts down the currently running kernel.
---
--- These keybindings make interacting with the REPL buffer intuitive and efficient.
---
--- # Highlight groups ~
---
--- * `JupytermInText` - Titles of input blocks in REPL buffer
--- * `JupytermOutText` - Titles of output blocks in REPL buffer
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
  Jupyterm.ns_in = vim.api.nvim_create_namespace("jupyterm-in")
  Jupyterm.ns_out = vim.api.nvim_create_namespace("jupyterm-out")
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
          execute.send(args[1], table.concat(opts.fargs, "", 3, #opts.fargs))
        else
          execute.send_line(args[1])
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
        display.toggle_repl(unpack(args))
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
        -- Filter subcommands that match
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

  -- Set configs for REPL windows/buffers
  vim.api.nvim_create_autocmd("FileType", {
    group = "Jupyterm",
    pattern = "jupyterm-*",
    callback = function()
      -- Identify language
      local buf_name = vim.api.nvim_buf_get_name(0)
      local language = "python"
      local kernel_name = "python3"
      for k,v in pairs(Jupyterm.kernel_to_lang) do
        if string.find(buf_name, ":"..k..":") then
          language = v
          kernel_name = k
        end
      end

      -- Syntax highlighting
      vim.api.nvim_set_option_value("syntax", "on", {buf = 0})
      local bufnr = vim.api.nvim_get_current_buf()
      local status, _ = pcall(require, 'nvim-treesitter')
      Jupyterm.jupystring[bufnr] = "```"..language
      if status then
        vim.treesitter.language.register("markdown", 'jupyterm-'..kernel_name)
        vim.cmd[[TSBufEnable highlight]]
      else
        if vim.g.markdown_fenced_languages then
          table.insert(vim.g.markdown_fenced_languages, language)
        else
          vim.g.markdown_fenced_languages = {language}
        end
        vim.cmd("setlocal syntax=markdown")
      end

      -- Options and keybindings
      vim.bo.tabstop = 4
      vim.bo.shiftwidth = 4
      vim.bo.expandtab = true
      vim.keymap.set("n", "<cr>", execute.send_display_block, {desc="Send display block", buffer=0})
      vim.keymap.set("n", "[c", display.jump_display_block_up, {desc="Jump up one display block", buffer=0})
      vim.keymap.set("n", "]c", display.jump_display_block_down, {desc="Jump down one display block", buffer=0})
      vim.keymap.set("n", "<esc>", function() display.show_repl(nil, true) end, {desc="Refresh", buffer=0})
      vim.keymap.set("n", "<c-c>", manage_kernels.interrupt_kernel, {desc="Interrupt", buffer=0})
      vim.keymap.set("n", "<c-q>", manage_kernels.shutdown_kernel, {desc="Shutdown", buffer=0})
    end
  })

  -- Periodically refresh displayed windows
  if Jupyterm.config.output_refresh.enabled then
    local refresh_buf_timer = vim.loop.new_timer()
    local delay = Jupyterm.config.output_refresh.delay
    refresh_buf_timer:start(delay, delay, vim.schedule_wrap(display.refresh_windows))
    local refresh_virt_text_timer = vim.loop.new_timer()
    local delay = Jupyterm.config.output_refresh.delay
    refresh_virt_text_timer:start(delay, delay, vim.schedule_wrap(display.refresh_virt_text))
  end

  -- Clean up jupyterms on exit (helps session management)
  vim.api.nvim_create_autocmd({"ExitPre"}, {
    group = "Jupyterm",
    pattern="*",
    callback = function()
      -- Close all open jupyterm windows
      for k,_ in pairs(Jupyterm.kernels) do
        if utils.is_repl_showing(k) then
          local kernel_win = Jupyterm.kernels[k].show_win.winid
          vim.api.nvim_win_close(kernel_win, true)
        end
      end
    end
  })

  -- Only allow REPL buffers in jupyterm windows
  local major = vim.version().major
  local minor = vim.version().minor
  if (major < 1) and (minor > 9) then
    vim.api.nvim_create_autocmd({"BufWinEnter"}, {
      group = "Jupyterm",
      pattern = "jupyterm:*",
      callback = function()
        vim.o.winfixbuf = true
      end
    })
  else
    -- Handle buffer switching for versions below 0.9
    vim.api.nvim_create_autocmd({"BufWinEnter"}, {
      group = "Jupyterm",
      pattern = "*",
      callback = function()
        local prev_file_nuiterm = vim.api.nvim_eval('bufname("#") =~ "jupyterm:"')
        local cur_file_nuiterm = vim.api.nvim_eval('bufname("%") =~ "jupyterm:"')
        local prev_bufwin = vim.api.nvim_eval('win_findbuf(bufnr("#"))')
        if (prev_file_nuiterm == 1) and (cur_file_nuiterm == 0) and (#prev_bufwin == 0) then
          vim.schedule(function()vim.cmd[[b#]]end)
        end
      end
    })
  end

  -- Keep track of REPL buffer edits to avoid overwriting on refresh
  vim.api.nvim_create_autocmd({"ModeChanged"}, {
    group = "Jupyterm",
    pattern = {"n:[vViRsS\x16\x13]*", "n:no*"},
    callback = function()
      -- Mark kernel as edited if REPL buffer is modified
      local bufnr = vim.api.nvim_get_current_buf()
      local filename = vim.api.nvim_buf_get_name(bufnr)
      if filename:match("jupyterm:*") then
        local kernel = utils.get_kernel_if_in_kernel_buf()
        if kernel then
          Jupyterm.kernels[kernel].edited = true
        end
      end
    end
  })
end

_G.Jupyterm = Jupyterm
return Jupyterm
