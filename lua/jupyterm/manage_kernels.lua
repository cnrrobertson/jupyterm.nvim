---@tag Jupyterm.manage_kernels
---@signature Jupyterm.manage_kernels
local utils = require("jupyterm.utils")

local manage_kernels = {}

--- Selects a kernel from the available kernels.
---@param new boolean?
---@return string
function manage_kernels.select_kernel(new)
  local kernel_keys = vim.tbl_keys(Jupyterm.kernels)
  local return_val = nil
  if new then
    vim.ui.input({
      prompt = "New kernel name: ",
      default = utils.get_kernel_buf_or_buf(),
    }, function(name)
        if name then
          return_val = tostring(name)
        end
      end
    )
  elseif #kernel_keys == 0 then
    vim.ui.input({
      prompt = "No kernels running! New kernel name: ",
      default = utils.get_kernel_buf_or_buf(),
    }, function(name)
        if name then
          return_val = tostring(name)
        end
      end
    )
  else
    vim.ui.select(kernel_keys, {
      prompt = "Select a kernel: ",
    }, function(choice)
        if choice then
          return_val = tostring(choice)
        end
      end
    )
  end
  return return_val or utils.get_kernel_buf_or_buf()
end

--- Starts a Jupyter kernel.
---@param kernel string?
---@param cwd string? where the kernel should start, default: buffer location
---@param kernel_name string?
function manage_kernels.start_kernel(kernel, cwd, kernel_name)
  kernel = kernel or manage_kernels.select_kernel(true)
  cwd = cwd or vim.fn.expand("%:p:h")
  if Jupyterm.kernels[kernel] then
    vim.print("Kernel "..kernel.." has already been started.")
  else
    kernel_name = kernel_name or Jupyterm.config.default_kernel
    local queue_str = Jupyterm.config.ui.queue_str
    local wait_str = Jupyterm.config.ui.wait_str
    vim.fn.JupyStart(kernel, cwd, kernel_name, wait_str, queue_str)
    Jupyterm.kernels[kernel] = {
      kernel_name=kernel_name,
      edited=nil,
      show_win=nil,
      show_buf=nil,
      show_full_output=nil,
      show_virt=true,
      virt_buf=nil,
      virt_text={},
      virt_olocs={},
      virt_extmarks={},
    }
  end
end

--- Shuts down a Jupyter kernel.
---@param kernel string?
function manage_kernels.shutdown_kernel(kernel)
  kernel = utils.get_kernel(kernel)
  if Jupyterm.kernels[kernel].show_win then
    Jupyterm.kernels[kernel].show_win:unmount()
  end
  if utils.is_virt_text_showing(kernel) then
    vim.api.nvim_buf_clear_namespace(
      Jupyterm.kernels[kernel].virt_buf,
      Jupyterm.ns_virt,
      0,
      -1
    )
  end
  Jupyterm.kernels[kernel] = nil
  vim.fn.JupyShutdown(tostring(kernel))
end

--- Interrupts a Jupyter kernel.
---@param kernel string?
function manage_kernels.interrupt_kernel(kernel)
  kernel = utils.get_kernel(kernel)
  vim.fn.JupyInterrupt(tostring(kernel))
end

--- Checks the status of a Jupyter kernel.
---@param kernel string?
function manage_kernels.check_kernel_status(kernel)
  kernel = utils.get_kernel(kernel)
  vim.fn.JupyStatus(tostring(kernel))
end

return manage_kernels
