#!/usr/bin/env bash

pass_count=0
warn_count=0
fail_count=0

ok() {
  pass_count=$((pass_count + 1))
  printf '[OK] %s\n' "$1"
}

warn() {
  warn_count=$((warn_count + 1))
  printf '[WARN] %s\n' "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf '[FAIL] %s\n' "$1"
}

check_file_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    ok "file exists: ${file#"$BASE_DIR"/}"
  else
    fail "missing file: ${file#"$BASE_DIR"/}"
  fi
}

print_selfcheck_summary() {
  printf '\nSummary: %d passed, %d warnings, %d failed\n' "$pass_count" "$warn_count" "$fail_count"

  if [ "$fail_count" -gt 0 ]; then
    exit 1
  fi

  exit 0
}
