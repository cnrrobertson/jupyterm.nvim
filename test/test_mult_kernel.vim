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
JupyOutputBuf 1

JupyStart 2
JupyExec 2 print("Kernel 2")
JupyExec 2 x = 2
JupyExec 2 y = 1
JupyExec 2 z = x + y
JupyExec 2 print(z)
JupyExec 2 z
JupyExec 2 x = 1; y = 2; print(x + y)
JupyOutputBuf 2
" JupyShutdown
