local layout = {}

--- Calculates a dimension from a size spec (percentage string, fraction, or absolute).
---@param size string|number e.g. "40%", 0.4, or 30
---@param max_dimension integer the max (vim.o.columns or vim.o.lines)
---@return integer
local function calculate_dimension(size, max_dimension)
  if type(size) == "string" then
    local pct = tonumber(string.sub(size, 1, -2))
    if pct then
      return math.max(1, math.floor(max_dimension * pct / 100))
    end
    return math.max(1, math.floor(max_dimension * 0.4))
  end
  if size > 0 and size < 1 then
    return math.max(1, math.floor(max_dimension * size))
  end
  return math.max(1, math.floor(size))
end

--- Opens a window with standard defaults.
---@param bufnr integer
---@param enter boolean
---@param opts vim.api.keyset.win_config
---@param win_opts? table<string, any>
---@return integer winid
local function open_win(bufnr, enter, opts, win_opts)
  local default_opts = {
    split = "right",
    win = -1,
    noautocmd = true,
    style = "minimal",
  }
  local config = vim.tbl_deep_extend("force", default_opts, opts)
  local winid = vim.api.nvim_open_win(bufnr, enter, config)

  local merged = vim.tbl_deep_extend("force", {
    wrap = true,
    linebreak = true,
    winfixbuf = true,
  }, win_opts or {})

  for name, value in pairs(merged) do
    vim.api.nvim_set_option_value(name, value, { win = winid })
  end

  return winid
end

--- Opens the full three-pane layout.
---@param buf_nrs { output: integer, variables: integer, input: integer }
---@param win_nrs { output: integer?, variables: integer?, input: integer? }
---@param cfg { position: string, width: string|number, height: string|number, input_height: integer }
function layout.open(buf_nrs, win_nrs, cfg)
  local position = cfg.position or "right"
  local is_bottom = position == "bottom"
  local split_direction = is_bottom and "below"
    or (position == "left" and "left" or "right")

  -- 1. Output window (primary split from editor)
  if not (win_nrs.output and vim.api.nvim_win_is_valid(win_nrs.output)) then
    local output_opts = {
      win = -1,
      split = split_direction,
    }
    if is_bottom then
      output_opts.height = calculate_dimension(cfg.height, vim.o.lines)
    else
      output_opts.width = calculate_dimension(cfg.width, vim.o.columns)
    end
    win_nrs.output = open_win(buf_nrs.output, false, output_opts, {
      winfixwidth = not is_bottom,
      winfixheight = is_bottom,
      scrolloff = 4,
    })
  end

  -- 2. Input window (splits below output)
  if not (win_nrs.input and vim.api.nvim_win_is_valid(win_nrs.input)) then
    local input_opts = {
      win = win_nrs.output,
      split = "below",
      height = cfg.input_height or 10,
    }
    win_nrs.input = open_win(buf_nrs.input, false, input_opts, {
      winfixheight = true,
    })
  end
end

--- Opens or resizes the variables pane between output and input.
---@param buf_nrs { output: integer, variables: integer, input: integer }
---@param win_nrs { output: integer?, variables: integer?, input: integer? }
---@param max_height integer
function layout.open_variables(buf_nrs, win_nrs, max_height)
  if not (win_nrs.output and vim.api.nvim_win_is_valid(win_nrs.output)) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(buf_nrs.variables)
  local height = math.min(math.max(line_count + 1, 3), max_height)

  local winid = win_nrs.variables
  if winid and vim.api.nvim_win_is_valid(winid) then
    -- Resize existing
    vim.api.nvim_win_set_config(winid, { height = height })
  else
    -- Create between output and input: split below output
    -- We split from the input window using "above" so it lands between output and input
    local ref_win = win_nrs.input
    if not (ref_win and vim.api.nvim_win_is_valid(ref_win)) then
      ref_win = win_nrs.output
    end
    win_nrs.variables = open_win(buf_nrs.variables, false, {
      win = ref_win,
      split = "above",
      height = height,
    }, {
      winfixheight = true,
    })
  end
end

--- Closes the variables window only.
---@param win_nrs { output: integer?, variables: integer?, input: integer? }
function layout.close_variables(win_nrs)
  local winid = win_nrs.variables
  if winid and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
  win_nrs.variables = nil
end

--- Closes all windows (preserves buffers).
---@param win_nrs { output: integer?, variables: integer?, input: integer? }
function layout.close_all(win_nrs)
  for name, winid in pairs(win_nrs) do
    if winid and vim.api.nvim_win_is_valid(winid) then
      pcall(vim.api.nvim_win_close, winid, true)
    end
    win_nrs[name] = nil
  end
end

return layout
