#!/usr/bin/env bash
# Run each neosnip test spec in an isolated nvim process.
# Usage: tests/run.sh [spec ...]    (default: all specs)
set -u
cd "$(dirname "$0")/.."

SPECS=(trigger_spec regex_spec snipmate_spec integration_spec behavior_spec misc_spec path_spec)
if [ $# -gt 0 ]; then
  SPECS=("$@")
fi

failed=0
for spec in "${SPECS[@]}"; do
  out=$(nvim --headless -u NONE \
    -c "lua vim.g.TEST_SPEC='${spec}'" \
    -c "luafile tests/single.lua" 2>&1)
  code=$?
  echo "== ${spec} =="
  echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -v '^  \['  # keep describe + summary lines
  if [ $code -ne 0 ]; then
    echo "  >>> ${spec}: FAILED (exit $code)"
    echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep 'FAIL' | sed 's/^/    /'
    failed=1
  fi
done

if [ $failed -ne 0 ]; then
  echo "Some specs FAILED"
  exit 1
fi
echo "All specs passed."
