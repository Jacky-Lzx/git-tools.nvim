#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
(cd "$root" && nvim --headless -u NONE -i NONE --noplugin -l tests/setup_contract.lua)
(cd "$root" && nvim --headless -u NONE -i NONE --noplugin -l tests/command_ownership.lua)
(cd "$root" && nvim --headless -u NONE -i NONE --noplugin -l tests/state.lua)
export GIT_TOOLS_ROOT="$root"
export SELECTION_TOOLS_DIR="${SELECTION_TOOLS_DIR:-$root/../selection-tools.nvim}"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT HUP INT TERM
export XDG_STATE_HOME="$test_tmp/state"
export XDG_CACHE_HOME="$test_tmp/cache"
export NVIM_LOG_FILE="$test_tmp/nvim.log"
for name in highlights unified native side_by_side top_bottom wrap syntax_sources syntax_injections git_sources native_theme render repository browse browse_targets hunks views lazygit lazygit_theme file_actions changes refs; do
  nvim --headless -u NONE -n -i NONE -l "$root/tests/$name.lua"
done
if [ -f "$SELECTION_TOOLS_DIR/lua/selection_tools/init.lua" ]; then
  nvim --headless -u NONE -n -i NONE -l "$root/tests/selection.lua"
  nvim --headless -u NONE -n -i NONE -l "$root/tests/workflows.lua"
else
  echo "SKIP optional selection-tools integration (set SELECTION_TOOLS_DIR)"
fi
