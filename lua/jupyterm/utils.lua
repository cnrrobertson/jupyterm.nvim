local utils = {}

---Checks if the buffer is a jupyterm buffer
---@param buf integer
---@return boolean
function utils.is_jupyterm(buf)
  local ft = vim.api.nvim_get_option_value("filetype", {buf=buf})
  local jupy_name = string.find(ft, "jupyterm")
  return jupy_name ~= nil
end

---Finds the kernel associated with the given buffer
---@param buf integer
---@return string?
function utils.find_kernel(buf)
  for k,v in pairs(Jupyterm.kernels) do
    if v.show_buf and v.show_buf == buf then
      return k
    end
  end
end

---Gets the kernel if the current buffer is a Jupyter REPL buffer
---@return string?
function utils.get_kernel_if_in_kernel_buf()
  if utils.is_jupyterm(vim.api.nvim_get_current_buf()) then
    return utils.find_kernel(vim.api.nvim_get_current_buf())
  end
end

---Generates a kernel name based on the current buffer.
---@return string
function utils.make_kernel_name()
  local buf = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(buf)
  bufname = vim.fn.fnamemodify(bufname, ":.")
  return "buf:"..buf..":"..bufname
end

---Gets kernel buffer name, or creates one if it doesn't exist
---@return string
function utils.get_kernel_buf_or_buf()
  local kernel_buf_name = utils.make_kernel_name()
  return utils.get_kernel_if_in_kernel_buf() or kernel_buf_name
end

---Splits a string by newlines
---@param input string
---@return string[]
function utils.split_by_newlines(input)
  local result = {}
  local clean_input = input:gsub("%^@", "\n")
  for line in clean_input:gmatch("([^\n]*)\n?") do
    table.insert(result, line)
  end
  return result
end

---Strips leading and trailing whitespace from a string.
---@param s string
---@return string
function utils.strip(s)
    return s:match("^%s*(.-)%s*$")
end

---Gets length of a table with keywords
---@param t table
---@return integer
function utils.table_length(t)
  local length = 0
  for _,_ in pairs(t) do
    length = length + 1
  end
  return length
end

---Renames a buffer and handles potential duplicate terminal buffer issues
---@param bufnr number
---@param name string
function utils.rename_buffer(bufnr, name)
  vim.api.nvim_buf_set_name(bufnr, name)
  -- Renaming causes duplication of terminal buffer -> delete old buffer
  -- https://github.com/neovim/neovim/issues/20349
  local alt = vim.api.nvim_buf_call(bufnr, function()
    return vim.fn.bufnr('#')
  end)
  if alt ~= bufnr and alt ~= -1 then
    pcall(vim.api.nvim_buf_delete, alt, {force=true})
  end
end

--- Gets the namespace extmark above the line.
---@param cur_line integer current line
---@param ns_id integer namespace id
---@return table? extmark or nil
function utils.get_extmark_above(cur_line, ns_id)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, {0,0}, {cur_line-1,0}, {details=true, overlap=true})
  if #extmarks > 0 then
    return extmarks[#extmarks]
  end
end

--- Gets the namespace extmark below the line
---@param cur_line integer current line
---@param ns_id integer namespace id
---@return table? extmark or nil
function utils.get_extmark_below(cur_line, ns_id)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, {cur_line,0}, {-1,0}, {details=true, overlap=true})
  if #extmarks > 0 then
    return extmarks[1]
  end
end

return utils
