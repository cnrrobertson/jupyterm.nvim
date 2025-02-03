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

function utils.make_kernel_name()
  local buf = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(buf)
  bufname = vim.fn.fnamemodify(bufname, ":.")
  return "buf:"..buf..":"..bufname
end

function utils.get_kernel_buf_or_buf()
  kernel_buf_name = utils.make_kernel_name()
  return utils.get_kernel_if_in_kernel_buf() or kernel_buf_name
end

function utils.split_by_newlines(input)
  local result = {}
  local clean_input = input:gsub("%^@", "\n")
  for line in clean_input:gmatch("([^\n]*)\n?") do
    table.insert(result, line)
  end
  return result
end

function utils.strip(s)
    return s:match("^%s*(.-)%s*$")
end

function utils.dict_length(t)
  local length = 0
  for _,_ in pairs(t) do
    length = length + 1
  end
  return length
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
