#!/bin/zsh
# Runs the core package tests and prints a compact summary (full log in $1 or .build/test.log).
set -o pipefail
LOG=${1:-Packages/EasyControlCore/.build/test.log}
swift test --package-path "$(dirname "$0")/../Packages/EasyControlCore" ${@:2} > "$LOG" 2>&1
STATUS=$?
grep -E "✘|error:|Test run with [1-9]" "$LOG" | sed 's/\x1b\[[0-9;]*m//g' | sort -u | tail -40
exit $STATUS
