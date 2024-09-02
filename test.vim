set runtimepath+=~/Software/jupyterm.nvim
silent UpdateRemotePlugins

lua require("jupyterm")

JupyStart
JupyExec x = 20
JupyExec y = 10
JupyExec z = x + y
JupyExec print(z)
JupyExec x
JupyExec y
JupyExec z
JupyExec x = 10; y = 20; print(x + y)
JupyShow

lua Jupyterm.send("x = 12\ny = 200\nprint(x + y)")

lua Jupyterm.send("import numpy as np\nimport matplotlib.pyplot as plt\nx = np.linspace(0,10,100)\ny = np.sin(x)\nplt.plot(x,y)\nplt.show()")

lua Jupyterm.send("import numpy as np")
lua Jupyterm.send("for i in range(100000):\n    x=np.random.rand(100,100)\n    b=np.random.rand(100)\n    np.linalg.solve(x,b)\nprint('done')")
" lua Jupyterm.send("for i in range(100000):\n    x=np.random.rand(100,100)\n    b=np.random.rand(100)\n    np.linalg.solve(x,b)")

" JupyShutdown
