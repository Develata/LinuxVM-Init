#!/usr/bin/env bash

write_mock_ip_command() {
  local dir="$1"
  local mode="$2"
  {
    printf '%s\n' '#!/bin/sh'
    printf "mode='%s'\n" "$mode"
    printf '%s\n' 'case "$*" in'
    printf '%s\n' '  "-4 -o addr show scope global")'
    printf '%s\n' '    case "$mode" in ipv4|dual) printf "%s\n" "2: eth0 inet 192.0.2.10/24 scope global eth0"; exit 0 ;; esac'
    printf '%s\n' '    exit 1'
    printf '%s\n' '    ;;'
    printf '%s\n' '  "-6 -o addr show scope global")'
    printf '%s\n' '    case "$mode" in ipv6|dual) printf "%s\n" "2: eth0 inet6 2001:db8::10/64 scope global"; exit 0 ;; esac'
    printf '%s\n' '    exit 1'
    printf '%s\n' '    ;;'
    printf '%s\n' '  "-4 route show default")'
    printf '%s\n' '    case "$mode" in ipv4-route) printf "%s\n" "default via 192.0.2.1 dev eth0"; exit 0 ;; esac'
    printf '%s\n' '    exit 1'
    printf '%s\n' '    ;;'
    printf '%s\n' '  "-6 route show default")'
    printf '%s\n' '    case "$mode" in ipv6-route) printf "%s\n" "default via fe80::1 dev eth0"; exit 0 ;; esac'
    printf '%s\n' '    exit 1'
    printf '%s\n' '    ;;'
    printf '%s\n' 'esac'
    printf '%s\n' 'exit 1'
  } >"$dir/ip"
  chmod +x "$dir/ip"
}

check_network_stack_detect_case() {
  local label="$1"
  local mock_mode="$2"
  local expected="$3"
  local tmpbin old_path result
  tmpbin="$(mktemp -d /tmp/linuxvm-init-selfcheck-network.XXXXXX)" || {
    fail "failed to create network stack selfcheck temp dir: $label"
    return
  }

  if [ "$mock_mode" != 'missing' ]; then
    write_mock_ip_command "$tmpbin" "$mock_mode"
    old_path="$PATH"
    PATH="$tmpbin:$old_path"
  else
    old_path="$PATH"
    PATH="$tmpbin"
  fi
  result="$(network_stack_detect)"
  PATH="$old_path"
  rm -rf "$tmpbin"

  if [ "$result" = "$expected" ]; then
    ok "network stack detection: $label"
  else
    fail "network stack detection: $label expected $expected got $result"
  fi
}

check_network_stack_detection() {
  check_network_stack_detect_case 'ipv4 only' 'ipv4' 'ipv4'
  check_network_stack_detect_case 'ipv6 only' 'ipv6' 'ipv6'
  check_network_stack_detect_case 'dual stack' 'dual' 'dual'
  check_network_stack_detect_case 'ipv4 default route' 'ipv4-route' 'ipv4'
  check_network_stack_detect_case 'ipv6 default route' 'ipv6-route' 'ipv6'
  check_network_stack_detect_case 'ip command missing' 'missing' 'unknown'
}

check_network_stack_render_case() {
  local stack="$1"
  local tmp_file
  tmp_file="$(mktemp /tmp/linuxvm-init-selfcheck-stack-rules.XXXXXX)" || {
    fail "failed to create network stack render temp file: $stack"
    return
  }

  if ! nftables_render_ruleset "$tmp_file" 34521 '2001:db8::1' '80,443' '53' 'essential' 'docker' "$stack"; then
    fail "network stack ruleset render failed: $stack"
    rm -f "$tmp_file"
    return
  fi

  case "$stack" in
    ipv4)
      if grep -q 'meta nfproto ipv4 tcp dport 34521' "$tmp_file" \
        && grep -q 'icmp-essential-v4' "$tmp_file" \
        && ! grep -q 'icmp-essential-v6' "$tmp_file"; then
        ok 'network stack ruleset render: ipv4'
      else
        fail 'network stack ruleset render: ipv4'
      fi
      ;;
    ipv6)
      if grep -q 'meta nfproto ipv6 tcp dport 34521' "$tmp_file" \
        && grep -q 'icmp-essential-v6' "$tmp_file" \
        && ! grep -q 'icmp-essential-v4' "$tmp_file"; then
        ok 'network stack ruleset render: ipv6'
      else
        fail 'network stack ruleset render: ipv6'
      fi
      ;;
    dual)
      if grep -q 'tcp dport 34521' "$tmp_file" \
        && grep -q 'icmp-essential-v4' "$tmp_file" \
        && grep -q 'icmp-essential-v6' "$tmp_file"; then
        ok 'network stack ruleset render: dual'
      else
        fail 'network stack ruleset render: dual'
      fi
      ;;
  esac
  rm -f "$tmp_file"
}

check_network_stack_rendering() {
  check_network_stack_render_case 'ipv4'
  check_network_stack_render_case 'ipv6'
  check_network_stack_render_case 'dual'
}
