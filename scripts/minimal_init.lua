-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up deps
vim.cmd('set rtp+=deps/mini.nvim')
require('mini.doc').setup()
require('mini.test').setup()

vim.cmd('set rtp+=deps/nui.nvim')
