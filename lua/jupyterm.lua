local config = require("jupyterm.config")
local utils = require("jupyterm.utils")
local display = require("jupyterm.display")
local manage_kernels = require("jupyterm.manage_kernels")
local execute = require("jupyterm.execute")
local menu = require("jupyterm.menu")

local Jupyterm = {kernels={}, send_memory={}, edited={}, jupystring={}}

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

function Jupyterm.setup(opts)
  opts = nil or {}

  -- Update config
  Jupyterm.config = vim.tbl_deep_extend("force", config, opts)

  -- Setup filetypes, namespaces, highlight groups
  vim.api.nvim_create_augroup("Jupyterm", {clear = true})
  Jupyterm.ns_in = vim.api.nvim_create_namespace("jupyterm-in")
  Jupyterm.ns_out = vim.api.nvim_create_namespace("jupyterm-out")
  vim.api.nvim_set_hl(0, "JupytermInText", {link = "@markup.heading.2.markdown", default = true})
  vim.api.nvim_set_hl(0, "JupytermOutText", {link = "Identifier", default = true})

  -- Setup user commands
  vim.api.nvim_create_user_command("JupyStart", function(args) manage_kernels.start_kernel(unpack(args.fargs)) end, {nargs="*"})
  vim.api.nvim_create_user_command("JupyShutdown", function(args) manage_kernels.shutdown_kernel(unpack(args.fargs)) end, {nargs="?"})
  vim.api.nvim_create_user_command("JupyStatus", function(args) manage_kernels.check_kernel_status(unpack(args.fargs)) end, {nargs="?"})
  vim.api.nvim_create_user_command("JupyInterrupt", function(args) manage_kernels.interrupt_kernel(unpack(args.fargs)) end, {nargs="?"})
  vim.api.nvim_create_user_command("JupyOutputBuf", function(args) display.toggle_outputs(unpack(args.fargs)) end, {nargs="?"})
  vim.api.nvim_create_user_command("JupyShow", function(args) display.show_outputs(unpack(args.fargs)) end, {nargs="*"})
  vim.api.nvim_create_user_command("JupyHide", function(args) display.hide_outputs(unpack(args.fargs)) end, {nargs="?"})
  vim.api.nvim_create_user_command("JupyMenu", function(args) menu.toggle_menu() end, {nargs=0})

  -- Set configs for output windows/buffers
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
      vim.keymap.set("n", "<esc>", function() display.show_outputs(nil, true) end, {desc="Refresh", buffer=0})
      vim.keymap.set("n", "<c-c>", manage_kernels.interrupt_kernel, {desc="Interrupt", buffer=0})
      vim.keymap.set("n", "<c-q>", manage_kernels.shutdown_kernel, {desc="Shutdown", buffer=0})
    end
  })

  -- Periodically refresh displayed windows
  if Jupyterm.config.output_refresh.enabled then
    local refresh_timer = vim.loop.new_timer()
    local delay = Jupyterm.config.output_refresh.delay
    refresh_timer:start(delay, delay, vim.schedule_wrap(display.refresh_windows))
  end

  -- Clean up jupyterms on exit (helps session management)
  vim.api.nvim_create_autocmd({"ExitPre"}, {
    group = "Jupyterm",
    pattern="*",
    callback = function()
      for k,_ in pairs(Jupyterm.kernels) do
        if display.is_showing(k) then
          local kernel_win = Jupyterm.kernels[k].show_win.winid
          vim.api.nvim_win_close(kernel_win, true)
        end
      end
    end
  })

  -- Only allow output buffers in jupyterm windows
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

  -- Keep track of output buffer edits to avoid overwriting on refresh
  vim.api.nvim_create_autocmd({"ModeChanged"}, {
    group = "Jupyterm",
    pattern = {"n:[vViRsS\x16\x13]*", "n:no*"},
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local filename = vim.api.nvim_buf_get_name(bufnr)

      -- Check if the filename matches the desired pattern
      if filename:match("jupyterm:*") then
        local kernel = utils.get_kernel_if_in_kernel_buf()
        if kernel then
          Jupyterm.edited[kernel] = true
        end
      end
    end
  })
end

_G.Jupyterm = Jupyterm
return Jupyterm
