#!/usr/bin/env bash

write_mock_iptables_command() {
  local dir="$1"
  local cmd="$2"
  local backend="$3"
  if [ "$backend" = 'missing' ]; then
    return
  fi

  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'if [ "${1:-}" = "--version" ]; then'
    printf "  printf 'iptables v1.8.10 (%%s)\\n' '%s'\n" "$backend"
    printf '%s\n' '  exit 0'
    printf '%s\n' 'fi'
    printf '%s\n' 'exit 0'
  } >"$dir/$cmd"
  chmod +x "$dir/$cmd"
}

check_iptables_frontend_case() {
  local label="$1"
  local ipv4_backend="$2"
  local ipv6_backend="$3"
  local expected="$4"
  local tmpbin old_path result
  tmpbin="$(mktemp -d /tmp/linuxvm-init-selfcheck-iptables.XXXXXX)" || {
    fail "failed to create iptables frontend selfcheck temp dir: $label"
    return
  }

  write_mock_iptables_command "$tmpbin" iptables "$ipv4_backend"
  write_mock_iptables_command "$tmpbin" ip6tables "$ipv6_backend"
  old_path="$PATH"
  PATH="$tmpbin"
  result="$(nftables_detect_iptables_frontend)"
  PATH="$old_path"
  rm -rf "$tmpbin"

  if [ "$result" = "$expected" ]; then
    ok "iptables frontend detection: $label"
  else
    fail "iptables frontend detection: $label expected $expected got $result"
  fi
}

check_iptables_frontend_detection() {
  check_iptables_frontend_case 'nf_tables' 'nf_tables' 'nf_tables' 'nft'
  check_iptables_frontend_case 'legacy' 'legacy' 'legacy' 'legacy'
  check_iptables_frontend_case 'mixed' 'nf_tables' 'legacy' 'mixed'
  check_iptables_frontend_case 'missing' 'missing' 'missing' 'missing'
}
