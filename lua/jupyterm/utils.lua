local utils = {}

function utils.is_jupyterm(buf)
    return string.find(vim.api.nvim_get_option_value("filetype", {buf=buf}), "jupyterm") ~= nil
end

function utils.find_kernel(buf)
  for k,v in pairs(Jupyterm.kernels) do
    if v.show_buf and v.show_buf == buf then
      return k
    end
  end
end

function utils.get_kernel_if_in_kernel_buf()
  if utils.is_jupyterm(vim.api.nvim_get_current_buf()) then
    return utils.find_kernel(vim.api.nvim_get_current_buf())
  end
end

function utils.get_kernel_buf_or_buf()
  local kernel_buf_name = "buf:"..vim.api.nvim_get_current_buf()
  return utils.get_kernel_if_in_kernel_buf() or kernel_buf_name
end

function utils.split_by_newlines(input)
    local result = {}
    for line in input:gmatch("([^\n]*)\n?") do
        table.insert(result, line)
    end
    return result
end

function utils.strip(s)
    return s:match("^%s*(.-)%s*$")
end

function utils.rename_buffer(bufnr, name)
  vim.api.nvim_buf_set_name(bufnr,name)
  -- Renaming causes duplication of terminal buffer -> delete old buffer
  -- https://github.com/neovim/neovim/issues/20349
  local alt = vim.api.nvim_buf_call(bufnr, function()
    return vim.fn.bufnr('#')
  end)
  if alt ~= bufnr and alt ~= -1 then
    pcall(vim.api.nvim_buf_delete, alt, {force=true})
  end
end

return utils
