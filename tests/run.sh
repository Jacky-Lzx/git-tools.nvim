#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
export GIT_TOOLS_ROOT="$root"
export SELECTION_TOOLS_DIR="${SELECTION_TOOLS_DIR:-$root/../selection-tools.nvim}"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT HUP INT TERM
export XDG_STATE_HOME="$test_tmp/state"
export XDG_CACHE_HOME="$test_tmp/cache"
export NVIM_LOG_FILE="$test_tmp/nvim.log"
for name in unified render repository browse; do
  nvim --headless -u NONE -n -i NONE -l "$root/tests/$name.lua"
done
if [ -f "$SELECTION_TOOLS_DIR/lua/selection_tools/init.lua" ]; then
  nvim --headless -u NONE -n -i NONE -l "$root/tests/selection.lua"
  nvim --headless -u NONE -n -i NONE -l "$root/tests/workflows.lua"
else
  echo "SKIP optional selection-tools integration (set SELECTION_TOOLS_DIR)"
fi
