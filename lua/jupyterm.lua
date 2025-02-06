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

---Update config, setup namespaces, highlight groups, user commands, autocmds, and timers
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
  vim.api.nvim_set_hl(0, "JupytermInText", {link = "@markup.heading.2.markdown", default = true})
  vim.api.nvim_set_hl(0, "JupytermOutText", {link = "Identifier", default = true})
  vim.api.nvim_set_hl(0, "JupytermVirtText", {link = "DiffText", default = true})

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
        vim.fn.JupyEval(unpack(args))
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
    hide_text = {
      impl = function(args, opts)
        display.hide_virt_text(unpack(args))
      end,
      complete = {"kernel", "start_row", "end_row"}
    },
    reveal_text = {
      impl = function(args, opts)
        display.show_virt_text_at_row(unpack(args))
      end,
      complete = {"kernel", "row"}
    },
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
  })
  -- Set configs for REPL windows/buffers
  vim.api.nvim_create_autocmd("FileType", {
    group = "Jupyterm",
    pattern = "jupyterm-*",
    callback = function()
      -- Identify language and set syntax, keymaps
      local buf_name = vim.api.nvim_buf_get_name(0)
      local language = "python"
      local kernel_name = "python3"
      for k,v in pairs(Jupyterm.kernel_to_lang) do
        if string.find(buf_name, ":"..k..":") then
          language = v
          kernel_name = k
        end
      end
      local status, _ = pcall(require, 'nvim-treesitter')
      if status then
        vim.api.nvim_set_option_value("syntax", "on", {buf = 0})
        vim.treesitter.language.register(language, 'jupyterm-'..kernel_name)
        vim.cmd[[TSBufEnable highlight]]
        local bufnr = vim.api.nvim_get_current_buf()
        Jupyterm.jupystring[bufnr] = "\"\"\""
      else
        vim.cmd("runtime! syntax/"..language..".vim")
        local bufnr = vim.api.nvim_get_current_buf()
        Jupyterm.jupystring[bufnr] = "#"
      end
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
        if display.is_showing(k) then
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
