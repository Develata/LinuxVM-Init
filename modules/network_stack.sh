#!/usr/bin/env bash

network_stack_detect_ipv4() {
  command -v ip >/dev/null 2>&1 || return 2
  ip -4 -o addr show scope global 2>/dev/null | awk 'NF { found = 1 } END { exit(found ? 0 : 1) }' \
    || ip -4 route show default 2>/dev/null | awk 'NF { found = 1 } END { exit(found ? 0 : 1) }'
}

network_stack_detect_ipv6() {
  command -v ip >/dev/null 2>&1 || return 2
  ip -6 -o addr show scope global 2>/dev/null | awk 'NF { found = 1 } END { exit(found ? 0 : 1) }' \
    || ip -6 route show default 2>/dev/null | awk 'NF { found = 1 } END { exit(found ? 0 : 1) }'
}

network_stack_normalize() {
  case "${1:-}" in
    ipv4|ipv6|dual|unknown) printf '%s\n' "$1" ;;
    *) printf '%s\n' 'unknown' ;;
  esac
}

network_stack_detect() {
  local has_ipv4='0'
  local has_ipv6='0'

  if ! command -v ip >/dev/null 2>&1; then
    printf '%s\n' 'unknown'
    return
  fi

  if network_stack_detect_ipv4; then
    has_ipv4='1'
  fi
  if network_stack_detect_ipv6; then
    has_ipv6='1'
  fi

  if [ "$has_ipv4" = '1' ] && [ "$has_ipv6" = '1' ]; then
    printf '%s\n' 'dual'
  elif [ "$has_ipv4" = '1' ]; then
    printf '%s\n' 'ipv4'
  elif [ "$has_ipv6" = '1' ]; then
    printf '%s\n' 'ipv6'
  else
    printf '%s\n' 'unknown'
  fi
}

network_stack_refresh() {
  local stack ipv4='0' ipv6='0' detected_at
  stack="$(network_stack_detect)"
  case "$stack" in
    ipv4) ipv4='1' ;;
    ipv6) ipv6='1' ;;
    dual)
      ipv4='1'
      ipv6='1'
      ;;
  esac

  detected_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  state_set 'NETWORK_IPV4_ENABLED' "$ipv4"
  state_set 'NETWORK_IPV6_ENABLED' "$ipv6"
  state_set 'NETWORK_STACK' "$stack"
  state_set 'NETWORK_STACK_DETECTED_AT' "$detected_at"
  printf '%s\n' "$stack"
}

network_stack_current() {
  local stack
  stack="$(state_get 'NETWORK_STACK')"
  network_stack_normalize "$stack"
}

network_stack_for_firewall() {
  local stack
  stack="$(network_stack_current)"
  case "$stack" in
    ipv4|ipv6|dual) printf '%s\n' "$stack" ;;
    *) printf '%s\n' 'dual' ;;
  esac
}

network_stack_supports_ipv4() {
  case "$(network_stack_normalize "$1")" in
    ipv4|dual|unknown) return 0 ;;
    *) return 1 ;;
  esac
}

network_stack_supports_ipv6() {
  case "$(network_stack_normalize "$1")" in
    ipv6|dual|unknown) return 0 ;;
    *) return 1 ;;
  esac
}

network_stack_show_state() {
  printf 'NETWORK_IPV4_ENABLED=%s\n' "$(state_get 'NETWORK_IPV4_ENABLED')"
  printf 'NETWORK_IPV6_ENABLED=%s\n' "$(state_get 'NETWORK_IPV6_ENABLED')"
  printf 'NETWORK_STACK=%s\n' "$(network_stack_current)"
  printf 'NETWORK_STACK_EFFECTIVE=%s\n' "$(network_stack_for_firewall)"
  printf 'NETWORK_STACK_DETECTED_AT=%s\n' "$(state_get 'NETWORK_STACK_DETECTED_AT')"
}
