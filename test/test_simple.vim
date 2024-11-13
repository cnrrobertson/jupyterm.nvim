set runtimepath+=~/Software/jupyterm.nvim
silent UpdateRemotePlugins

lua require("jupyterm")

JupyStart 1
JupyExec 1 x = 20
JupyExec 1 y = 10
JupyExec 1 z = x + y
JupyExec 1 print(z)
JupyExec 1 z
JupyExec 1 x = 10; y = 20; print(x + y)
JupyShow 1

