# jupyterm.nvim

`jupyterm.nvim` provides seamless integration with Jupyter kernels in Neovim.  It allows you to execute code, manage kernels, and view outputs within your Neovim editor. This includes a REPL buffer such as is available in [VSCode's Python Interactive window](https://code.visualstudio.com/docs/python/jupyter-support-py).

**Features:**

* Start, interrupt, and shutdown Jupyter kernels effortlessly.
* Send code blocks or selections to a selected kernel.
* View Jupyter outputs in REPL buffers or as virtual text inline with your code.
* Supports multiple languages via their respective Jupyter kernels (Python, R, Julia, etc.)


## Installation

### Python

Given this plugin interfaces with `Jupyter`, the following Python dependenices must be installed:

* `jupyter_client`
* `pynvim`
* `pillow` (optional - allows output images to be opened automatically)

### Neovim
**lazy.nvim**

```lua
{
  'cnrrobertson/jupyterm.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',
    'nvim-treesitter/nvim-treesitter', -- Optional, for improved syntax highlighting in REPL buffers
  },
  config = true,
  opts = {}
}
```

**packer.nvim**

```lua
{
  'cnrrobertson/jupyterm.nvim',
  requires = {
    'MunifTanjim/nui.nvim',
    'nvim-treesitter/nvim-treesitter', -- Optional, for improved syntax highlighting in REPL buffers
  },
  config = function()
    require("jupyterm").setup()
  end
}
```

**mini.deps**

```lua
{
  source = 'cnrrobertson/jupyterm.nvim',
  depends = {
    'MunifTanjim/nui.nvim',
    'nvim-treesitter/nvim-treesitter', -- Optional, for improved syntax highlighting in REPL buffers
  }
}
require("jupyterm").setup()
```

## Usage

1. **Start a Kernel:** Use the command `:Jupyter start <kernel> [<cwd> <kernel_name>]`. Replace `<kernel>` with a number/name for the kernel. Optionally, choose the working directory of the kernel with `<cwd>` and choose the language kernel with `<kernel_name>` (e.g., `python3`, `ir`, `ijulia`). By default, Neovim's `cwd` and the `python3` kernel are used.

2. **Send Code:** `:Jupyter execute <kernel>` will send the current line to the kernel. Visual selection then `:'<,'>Jupyter execute <kernel>` will send the selection to the kernel. Alternatively, send code directly via `:Jupyter execute <kernel> <code>`. See the `lua` API in the help file for `send_line`, `send_visual`, `send_select`, and `send_file` from `require("jupyterm.execute")` to send the current line, visual selection, to a selected kernel, and the entire current buffer respectively.

3. **Manage Kernels:** Use `:Jupyter status`, `:Jupyter interrupt`, `:Jupyter shutdown`, and `:Jupyter menu` to check the status, interrupt execution, shutdown a kernel, or view active kernels in an interactive popup menu.

4. **Output Display:** Outputs will appear in a dedicated REPL buffer or inline, depending on your configuration (`jupyterm.config.inline_display`). You can also use `:Jupyter toggle_repl` and `:Jupyter toggle_text` to manage the REPL buffer and virtual text respectively. Use `:Jupyter toggle_text_here` to toggle individual inline outputs.

5. **REPL:** After opening the REPL buffer with `:Jupyter toggle_repl`, the buffer may be edited as normal. Text inserted below the last `In [*]` in the buffer will be considered a new input. By default, hitting enter in normal mode will submit the input to the kernel. See the [REPL section](#repl) for more information on this buffer.

## User Commands

User commands are shown in the following table. Optional arguments are marked with a `?`:

| Command                    | Arguments                        | Description                                                     |
| ---------------            | --------------------------------- | --------------------------------------------------------------- |
| `Jupyter start`            | `kernel`, `cwd?`, `kernel_name?`  | Starts a Jupyter kernel.  `cwd` and `kernel_name` are optional. |
| `Jupyter shutdown`         | `kernel`                          | Shuts down a Jupyter kernel.                                    |
| `Jupyter status`           | `kernel`                          | Checks the status of a Jupyter kernel.                          |
| `Jupyter interrupt`        | `kernel`                          | Interrupts a Jupyter kernel.                                    |
| `Jupyter execute`          | `kernel?`, `code?`                | Executes code in a specified kernel.                            |
| `Jupyter menu`             | None                              | Toggles the Jupyter kernel menu.                                |
| `Jupyter toggle_repl`      | `kernel?`, `focus?`, `full?`      | Toggles the REPL window for a kernel.                           |
| `Jupyter toggle_text`      | `kernel?`                         | Toggles the display of virtual text outputs for a kernel.       |
| `Jupyter toggle_text_here` | `kernel`, `row?`                  | Toggles virtual text output in the range under the cursor.      |

Note that `kernel` generally refers to the kernel identifier in Neovim and not the `kernel_name` or the actual descriptor of a Jupyter kernel (e.g., `python3`, `ir`). Optional arguments can be omitted.

## REPL

The REPL (Read-Eval-Print Loop) buffer provides an interactive environment for executing code and viewing results. This buffer can be shown using `:Jupyter toggle_repl`. Text inserted *after* the last `In [*]` marker in this buffer is treated as a new input cell. Pressing Enter in normal mode will submit this input to the kernel.

The REPL buffer automatically refreshes to display updates from long-running computations. However, this automatic refresh pauses when you begin typing new input, preventing accidental overwriting.

To manage the length of the buffer and optimize refresh speed, the buffer's display is limited to a certain number of lines (configurable via `jupyterm.config.ui.max_displayed_lines`).  This prevents performance slowdowns from extremely large outputs. If needed, you can view the complete output by using the `full` argument of `Jupyter toggle_repl` or see the `lua` API in the help file.

The REPL buffer also comes with default keybindings for convenience:

* **`<CR>` (Enter):** Submits the current input to the kernel.
* **`<Esc>`:** Refreshes the display, showing the most current kernel output.
* **`[c`:** Jumps to the previous display block.
* **`]c`:** Jumps to the next display block.
* **`<C-c>`:** Interrupts the currently running kernel.
* **`<C-q>`:** Shuts down the currently running kernel.

These keybindings make interacting with the REPL buffer intuitive and efficient.

## Default Configuration

The default configuration is as follows:

```lua
config = {
  -- The default Jupyter kernel to use
  default_kernel = "python3",
  -- Focus the REPL window when showing
  focus_on_show = true,
  -- Show the REPL window when sending text to it
  show_on_send = false,
  -- Focus the REPL window when sending text to it
  focus_on_send = false,
  -- Show outputs inline as virtual text when sending text
  inline_display = true,
  -- Automatic refreshing of REPL window and virtual text
  output_refresh = {
    enabled = true,
    delay = 2000,
  },
  -- UI options for the REPL window and the menu
  ui = {
    format = "split",
    config = {
      relative = "editor",
      position = "right",
      size = "40%",
      enter = false
    },
    max_displayed_lines = 500,
    menu = {
      keys = {
        focus_next = {"j", "<Down>", "<Tab>"},
        focus_prev = {"k", "<Up>", "<S-Tab>"},
        submit = {"<CR>", "<Space>"},
        close = {"<Esc>", "<C-c>", "q"},
        new = {"n"},
        destroy = {"d"},
        toggle = {"w"},
      },
      opts = {
        relative = "editor",
        position = '50%',
        size = '50%',
        zindex = 500
      }
    }
  }
}
```

You can override these settings by calling `require("jupyterm").setup({})` with a table containing your custom options.

## Similar Plugins

*   [https://github.com/jupyterlab/jupyterlab](https://github.com/jupyterlab/jupyterlab): JupyterLab itself, the web-based Jupyter environment.  This plugin integrates with it, not replace it.
*   Other Neovim plugins that aim to provide similar functionality may exist, but they typically lack the flexibility and robust features offered by jupyterm.nvim.
