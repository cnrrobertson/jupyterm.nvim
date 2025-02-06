silent UpdateRemotePlugins

lua require("jupyterm")

Jupyter start 1
Jupyter execute 1 x = 20
Jupyter execute 1 y = 10
Jupyter execute 1 z = x + y
Jupyter execute 1 print(z)
Jupyter execute 1 z
Jupyter execute 1 x = 10; y = 20; print(x + y)
Jupyter toggle_repl 1

" Toggle
Jupyter toggle_repl 1
Jupyter toggle_repl 1
