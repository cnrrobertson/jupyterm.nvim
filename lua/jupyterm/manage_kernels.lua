local utils = require("jupyterm.utils")

local manage_kernels = {}

function manage_kernels.select_kernel()
  local kernel_keys = vim.tbl_keys(Jupyterm.kernels)
  local return_val = 1
  vim.ui.select(kernel_keys, {
    prompt = "Please select an option:",
  }, function(choice)
      return_val = choice
    end
  )
  return return_val
end

function manage_kernels.start_kernel(kernel, cwd, kernel_name)
  if kernel == nil then
    local buf = vim.api.nvim_get_current_buf()
    kernel = "buf:"..buf
    Jupyterm.send_memory[buf] = kernel
    cwd = vim.fn.expand("%:p:h")
  end
  if Jupyterm.kernels[kernel] then
    vim.print("Kernel "..kernel.." has already been started.")
  else
    kernel_name = kernel_name or Jupyterm.config.default_kernel
    vim.fn.JupyStart(kernel, cwd, kernel_name)
    Jupyterm.kernels[kernel] = {kernel_name=kernel_name}
  end
end

function manage_kernels.shutdown_kernel(kernel)
  if kernel == nil then
    kernel = utils.get_kernel_buf_or_buf()
  end
  if Jupyterm.kernels[kernel].show_win then
    vim.api.nvim_buf_delete(Jupyterm.kernels[kernel].show_win.bufnr, {force=true})
  end
  Jupyterm.kernels[kernel] = nil
  vim.fn.JupyShutdown(tostring(kernel))
end

function manage_kernels.interrupt_kernel(kernel)
  if kernel == nil then
    kernel = utils.get_kernel_buf_or_buf()
  end
  vim.fn.JupyInterrupt(tostring(kernel))
end

function manage_kernels.check_kernel_status(kernel)
  if kernel == nil then
    kernel = utils.get_kernel_buf_or_buf()
  end
  vim.fn.JupyStatus(tostring(kernel))
end

return manage_kernels
