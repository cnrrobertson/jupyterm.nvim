silent UpdateRemotePlugins

lua require("jupyterm")

Jupyter start 1
Jupyter execute 1 x = 20
Jupyter execute 1 y = 10
Jupyter execute 1 z = x + y
Jupyter execute 1 print(z)
Jupyter execute 1 z
Jupyter execute 1 x = 10; y = 20; print(x + y)
Jupyter toggle_term 1


lua require"jupyterm.execute".send(1, "x = 12\ny = 200\nprint(x + y)")

lua require"jupyterm.execute".send(1, "import numpy as np\nimport matplotlib.pyplot as plt\nx = np.linspace(0,10,100)\ny = np.sin(x)\nplt.plot(x,y)\nplt.show()")

lua require"jupyterm.execute".send(1, "import numpy as np")
lua require"jupyterm.execute".send(1, "for i in range(100000):\n    x=np.random.rand(100,100)\n    b=np.random.rand(100)\n    np.linalg.solve(x,b)\nprint('done')")
lua require"jupyterm.execute".send(1, "for i in range(100000):\n    x=np.random.rand(100,100)\n    b=np.random.rand(100)\n    np.linalg.solve(x,b)")

Jupyter start 2
Jupyter execute 2 print("Kernel 2")
Jupyter execute 2 x = 2
Jupyter execute 2 y = 1
Jupyter execute 2 z = x + y
Jupyter execute 2 print(z)
Jupyter execute 2 z
Jupyter execute 2 x = 1; y = 2; print(x + y)
Jupyter toggle_term 2
