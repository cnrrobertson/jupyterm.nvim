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


lua Jupyterm.send(1, "x = 12\ny = 200\nprint(x + y)")

lua Jupyterm.send(1, "import numpy as np\nimport matplotlib.pyplot as plt\nx = np.linspace(0,10,100)\ny = np.sin(x)\nplt.plot(x,y)\nplt.show()")

lua Jupyterm.send(1, "import numpy as np")
lua Jupyterm.send(1, "for i in range(100000):\n    x=np.random.rand(100,100)\n    b=np.random.rand(100)\n    np.linalg.solve(x,b)\nprint('done')")
lua Jupyterm.send(1, "for i in range(100000):\n    x=np.random.rand(100,100)\n    b=np.random.rand(100)\n    np.linalg.solve(x,b)")

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
