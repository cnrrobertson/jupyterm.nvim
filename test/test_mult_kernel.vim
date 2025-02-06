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

Jupyter start 2
Jupyter execute 2 print("Kernel 2")
Jupyter execute 2 x = 2
Jupyter execute 2 y = 1
Jupyter execute 2 z = x + y
Jupyter execute 2 print(z)
Jupyter execute 2 z
Jupyter execute 2 x = 1; y = 2; print(x + y)
Jupyter toggle_repl 2
