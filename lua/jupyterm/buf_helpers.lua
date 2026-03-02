local buf_helpers = {}

--- Temporarily makes a buffer modifiable, calls fn, then restores.
---@param bufnr integer
---@param fn fun(bufnr: integer): any
---@return any
function buf_helpers.with_modifiable(bufnr, fn)
  local was_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  local ok, result = pcall(fn, bufnr)
  vim.api.nvim_set_option_value("modifiable", was_modifiable, { buf = bufnr })
  if not ok then
    error(result)
  end
  return result
end

--- Returns true if buffer has no meaningful content.
---@param bufnr integer
---@return boolean
function buf_helpers.is_empty(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return true
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return true
  end
  if line_count == 1 then
    local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    return first_line == ""
  end
  return false
end

--- Creates an unlisted scratch buffer.
---@param opts? { filetype?: string }
---@return integer bufnr
function buf_helpers.create_scratch_buf(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  if opts.filetype then
    vim.api.nvim_set_option_value("filetype", opts.filetype, { buf = bufnr })
  end
  return bufnr
end

return buf_helpers
