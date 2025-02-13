---@tag Jupyterm.manage_kernels
---@signature Jupyterm.manage_kernels
local utils = require("jupyterm.utils")

local manage_kernels = {}

--- Selects a kernel from the available kernels.
---@return string?
function manage_kernels.select_kernel()
  local kernel_keys = vim.tbl_keys(Jupyterm.kernels)
  local return_val = nil
  vim.ui.select(kernel_keys, {
    prompt = "Please select an option:",
  }, function(choice)
      if choice then
        return_val = tostring(choice)
      end
    end
  )
  return return_val
end

--- Starts a Jupyter kernel.
---@param kernel string?
---@param cwd string?
---@param kernel_name string?
function manage_kernels.start_kernel(kernel, cwd, kernel_name)
  if kernel == nil then
    local buf = vim.api.nvim_get_current_buf()
    kernel = utils.make_kernel_name()
    Jupyterm.send_memory[buf] = kernel
    cwd = vim.fn.expand("%:p:h")
  end
  if Jupyterm.kernels[kernel] then
    vim.print("Kernel "..kernel.." has already been started.")
  else
    kernel_name = kernel_name or Jupyterm.config.default_kernel
    local queue_str = Jupyterm.config.ui.queue_str
    local wait_str = Jupyterm.config.ui.wait_str
    vim.fn.JupyStart(kernel, cwd, kernel_name, wait_str, queue_str)
    Jupyterm.kernels[kernel] = {kernel_name=kernel_name}
  end
end

--- Shuts down a Jupyter kernel.
---@param kernel string?
function manage_kernels.shutdown_kernel(kernel)
  kernel = kernel or utils.get_kernel_buf_or_buf()
  if utils.is_repl_showing(kernel) then
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
  kernel = kernel or utils.get_kernel_buf_or_buf()
  vim.fn.JupyInterrupt(tostring(kernel))
end

--- Checks the status of a Jupyter kernel.
---@param kernel string?
function manage_kernels.check_kernel_status(kernel)
  kernel = kernel or utils.get_kernel_buf_or_buf()
  vim.fn.JupyStatus(tostring(kernel))
end

return manage_kernels
