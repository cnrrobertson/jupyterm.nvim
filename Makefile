help:
	@sed -ne '/@sed/!s/## //p' $(MAKEFILE_LIST)

## ----------------------------------------------
##    Check configuration
##    -------------------
config: ##                            -- Generate diff of config in README vs lua/nuiterm/config.lua
	bash scripts/check-readme-config.sh lua/jupyterm/config.lua README.md

## ----------------------------------------------
##    Documentation
##    -------------
docs: deps ##                         -- Compile documentation from source files
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniDoc.generate({'lua/jupyterm.lua', 'lua/jupyterm/config.lua', 'lua/jupyterm/manage_kernels.lua', 'lua/jupyterm/execute.lua', 'lua/jupyterm/display.lua', 'lua/jupyterm/menu.lua'})" -c "quit"

## ----------------------------------------------
##    Tests
##    -----
# test: deps ##                         -- Run all tests in tests/ directory
# 	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c "quit"
#
# test_file: deps ##                    -- Run tests in given file
# 	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')" -c "quit"

## ----------------------------------------------
##    Dependencies
##    ------------
deps: deps/mini.nvim deps/nui.nvim ## -- Locally install dependencies in deps/ directory

deps/mini.nvim: ##                    -- Locally install mini.nvim dependency in deps/ directory
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $@

deps/nui.nvim: ##                     -- Locally install nui.nvim dependency in deps/ directory
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/MunifTanjim/nui.nvim $@
