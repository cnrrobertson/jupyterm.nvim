#!/usr/bin/env bash
# Originally taken from https://github.com/jedrzejboczar/possession.nvim

# Check if the defaults from config.lua are the same in README.md
# Poor but simple implementation based on sed and other standard tools.

defaults_file="$1"
readme_file="$2"

from_line() {
    tail -n "+$1"
}

# Retrieve the defaults table from config.lua
# 1. Get lines of the defaults() table
# 2. Remove the starting lines
config=$(
    sed -n '/^local config = {/,/^}/ p' "$defaults_file" \
        | from_line 2
)

# Get defaults from README
# 1. Lines of the Configuration section
# 2. Remove starting lines in code block
readme_config=$(
    sed -n '/^config = {/,/^}/ p' "$readme_file" \
        | from_line 2
)

diff -u <(echo "$config") <(echo "$readme_config")
