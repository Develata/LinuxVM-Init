#!/usr/bin/env bash

iptables_mode_command_for_family() {
  case "$1" in
    ipv4) printf '%s\n' 'iptables' ;;
    ipv6) printf '%s\n' 'ip6tables' ;;
    *) return 1 ;;
  esac
}

iptables_mode_insert_position() {
  local cmd="$1"
  local pos
  pos="$("$cmd" -nvL INPUT --line-numbers 2>/dev/null | awk '$0 ~ /f2b-sshd/ { line = $1 } END { if (line) print line + 1; else print 1 }')"
  case "$pos" in
    ''|*[!0-9]*) printf '%s\n' '1' ;;
    *) printf '%s\n' "$pos" ;;
  esac
}

iptables_mode_rule_exists() {
  local cmd="$1"
  shift
  "$cmd" -C INPUT "$@" >/dev/null 2>&1
}

iptables_mode_persistence_available() {
  [ -e /etc/iptables/rules.v4 ] || [ -e /etc/iptables/rules.v6 ] \
    || { is_installed systemctl && systemctl is-enabled netfilter-persistent >/dev/null 2>&1; }
}

iptables_mode_persist_rules() {
  local stack="${1:-}"
  local saved='0'
  local failed='0'
  local need_v4='0'
  local need_v6='0'
  if [ -z "$stack" ]; then
    stack="$(state_get 'NETWORK_STACK')"
  fi
  if [ -z "$stack" ] || [ "$stack" = 'unknown' ]; then
    stack="$(network_stack_refresh)"
  fi
  stack="$(network_stack_normalize "$stack")"

  if ! iptables_mode_persistence_available; then
    state_set 'FIREWALL_IPTABLES_PERSISTENCE' 'runtime-only'
    say '风险提示：未检测到 iptables 持久化配置，本次 iptables/ip6tables 规则可能在重启后丢失。' 'Warning: iptables/ip6tables persistence was not detected; these rules may be lost after reboot.'
    return 0
  fi

  if network_stack_supports_ipv4 "$stack"; then
    need_v4='1'
  fi
  if network_stack_supports_ipv6 "$stack"; then
    need_v6='1'
  fi
  if [ "$need_v4" != '1' ] && [ "$need_v6" != '1' ]; then
    state_set 'FIREWALL_IPTABLES_PERSISTENCE' 'runtime-only'
    say '风险提示：未检测到匹配当前网络栈的 iptables 持久化目标。' 'Warning: no iptables persistence target matched the current network stack.'
    return 0
  fi

  mkdir -p /etc/iptables
  if [ "$need_v4" = '1' ]; then
    if ! is_installed iptables-save; then
      failed='1'
    elif iptables-save >/etc/iptables/rules.v4; then
      saved='1'
    else
      failed='1'
    fi
  fi
  if [ "$need_v6" = '1' ]; then
    if ! is_installed ip6tables-save; then
      failed='1'
    elif ip6tables-save >/etc/iptables/rules.v6; then
      saved='1'
    else
      failed='1'
    fi
  fi
  if [ "$failed" = '1' ]; then
    state_set 'FIREWALL_IPTABLES_PERSISTENCE' 'failed'
    say 'iptables/ip6tables 规则保存失败，请检查 /etc/iptables 权限、磁盘空间或 iptables-save 输出。' 'Failed to persist iptables/ip6tables rules; check /etc/iptables permissions, disk space, or iptables-save output.'
    return 1
  fi
  if [ "$saved" = '1' ]; then
    state_set 'FIREWALL_IPTABLES_PERSISTENCE' 'saved'
    say 'iptables/ip6tables 规则已保存到当前网络栈对应的 /etc/iptables/rules.v4 或 rules.v6。' 'iptables/ip6tables rules saved to the matching /etc/iptables/rules.v4 or rules.v6 file for the current network stack.'
  fi
}

iptables_mode_warn_existing_wide_ssh_rule() {
  local port="$1"
  local source_ip="$2"
  local stack="$3"
  local warned='0'
  if is_valid_ipv4 "$source_ip" && network_stack_supports_ipv4 "$stack" && is_installed iptables; then
    if iptables_mode_rule_exists iptables -p tcp --dport "$port" -m comment --comment "linuxvm-init:tcp-${port}" -j ACCEPT \
      || iptables_mode_rule_exists iptables -p tcp --dport "$port" -j ACCEPT; then
      warned='1'
    fi
  elif is_valid_ipv6 "$source_ip" && network_stack_supports_ipv6 "$stack" && is_installed ip6tables; then
    if iptables_mode_rule_exists ip6tables -p tcp --dport "$port" -m comment --comment "linuxvm-init:tcp-${port}" -j ACCEPT \
      || iptables_mode_rule_exists ip6tables -p tcp --dport "$port" -j ACCEPT; then
      warned='1'
    fi
  fi

  if [ "$warned" = '1' ]; then
    say '风险提示：检测到同端口已有全来源放行规则；本次只新增来源白名单，不会自动收紧已有规则。' 'Warning: an existing broad allow rule for the same port was detected; this only adds a source allow rule and does not tighten existing rules.'
  fi
}

iptables_mode_add_input_rule() {
  local family="$1"
  shift
  local cmd pos
  cmd="$(iptables_mode_command_for_family "$family")" || return 1
  if ! is_installed "$cmd"; then
    say "${cmd} 未安装，无法添加 ${family} 规则。" "${cmd} is not installed; cannot add ${family} rule."
    return 1
  fi

  if iptables_mode_rule_exists "$cmd" "$@"; then
    return 0
  fi
  pos="$(iptables_mode_insert_position "$cmd")"
  run_argv "$cmd" -I INPUT "$pos" "$@"
}

iptables_mode_delete_input_rule() {
  local family="$1"
  shift
  local cmd deleted='0'
  cmd="$(iptables_mode_command_for_family "$family")" || return 1
  if ! is_installed "$cmd"; then
    say "${cmd} 未安装，跳过 ${family} 规则。" "${cmd} is not installed; skipping ${family} rule."
    return 0
  fi

  while iptables_mode_rule_exists "$cmd" "$@"; do
    run_argv "$cmd" -D INPUT "$@" || return 1
    deleted='1'
  done
  if [ "$deleted" != '1' ]; then
    say "${cmd} 中未找到对应的 linuxvm-init 规则，跳过。" "No matching linuxvm-init rule found in ${cmd}; skipping."
  fi
  return 0
}

iptables_mode_for_each_enabled_family() {
  local stack="$1"
  local fn="$2"
  shift 2
  local rc=0
  stack="$(network_stack_normalize "$stack")"
  if network_stack_supports_ipv4 "$stack"; then
    "$fn" ipv4 "$@" || rc=1
  fi
  if network_stack_supports_ipv6 "$stack"; then
    "$fn" ipv6 "$@" || rc=1
  fi
  return "$rc"
}

iptables_mode_add_tcp_port() {
  local port="$1"
  local stack="$2"
  iptables_mode_for_each_enabled_family "$stack" iptables_mode_add_input_rule -p tcp --dport "$port" -m comment --comment "linuxvm-init:tcp-${port}" -j ACCEPT
}

iptables_mode_add_udp_port() {
  local port="$1"
  local stack="$2"
  iptables_mode_for_each_enabled_family "$stack" iptables_mode_add_input_rule -p udp --dport "$port" -m comment --comment "linuxvm-init:udp-${port}" -j ACCEPT
}

iptables_mode_add_tcp_port_from_ip() {
  local port="$1"
  local source_ip="$2"
  local stack="$3"
  if ! is_valid_port "$port" || ! is_valid_ip "$source_ip"; then
    say 'SSH 来源 IP 或端口无效。' 'Invalid SSH source IP or port.'
    return 1
  fi

  if is_valid_ipv4 "$source_ip"; then
    if ! network_stack_supports_ipv4 "$stack"; then
      say '当前网络栈未启用 IPv4，拒绝添加 IPv4 来源白名单。' 'IPv4 is not enabled in the current network stack; refusing IPv4 source allow rule.'
      return 1
    fi
    iptables_mode_warn_existing_wide_ssh_rule "$port" "$source_ip" "$stack"
    iptables_mode_add_input_rule ipv4 -s "$source_ip" -p tcp --dport "$port" -m comment --comment "linuxvm-init:ssh-source-${port}" -j ACCEPT
  else
    if ! network_stack_supports_ipv6 "$stack"; then
      say '当前网络栈未启用 IPv6，拒绝添加 IPv6 来源白名单。' 'IPv6 is not enabled in the current network stack; refusing IPv6 source allow rule.'
      return 1
    fi
    iptables_mode_warn_existing_wide_ssh_rule "$port" "$source_ip" "$stack"
    iptables_mode_add_input_rule ipv6 -s "$source_ip" -p tcp --dport "$port" -m comment --comment "linuxvm-init:ssh-source-${port}" -j ACCEPT
  fi
}

iptables_mode_delete_tcp_port() {
  local port="$1"
  local stack="$2"
  iptables_mode_for_each_enabled_family "$stack" iptables_mode_delete_input_rule -p tcp --dport "$port" -m comment --comment "linuxvm-init:tcp-${port}" -j ACCEPT
}

iptables_mode_delete_udp_port() {
  local port="$1"
  local stack="$2"
  iptables_mode_for_each_enabled_family "$stack" iptables_mode_delete_input_rule -p udp --dport "$port" -m comment --comment "linuxvm-init:udp-${port}" -j ACCEPT
}

iptables_mode_add_icmp_family() {
  local family="$1"
  case "$family" in
    ipv4)
      iptables_mode_add_input_rule ipv4 -p icmp --icmp-type echo-request -m comment --comment 'linuxvm-init:icmp-essential-v4-echo-request' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv4 -p icmp --icmp-type destination-unreachable -m comment --comment 'linuxvm-init:icmp-essential-v4-destination-unreachable' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv4 -p icmp --icmp-type time-exceeded -m comment --comment 'linuxvm-init:icmp-essential-v4-time-exceeded' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv4 -p icmp --icmp-type parameter-problem -m comment --comment 'linuxvm-init:icmp-essential-v4-parameter-problem' -j ACCEPT
      ;;
    ipv6)
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type echo-request -m comment --comment 'linuxvm-init:icmp-essential-v6-echo-request' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type destination-unreachable -m comment --comment 'linuxvm-init:icmp-essential-v6-destination-unreachable' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type packet-too-big -m comment --comment 'linuxvm-init:icmp-essential-v6-packet-too-big' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type time-exceeded -m comment --comment 'linuxvm-init:icmp-essential-v6-time-exceeded' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type parameter-problem -m comment --comment 'linuxvm-init:icmp-essential-v6-parameter-problem' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type router-solicitation -m comment --comment 'linuxvm-init:icmp-essential-v6-router-solicitation' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type router-advertisement -m comment --comment 'linuxvm-init:icmp-essential-v6-router-advertisement' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type neighbor-solicitation -m comment --comment 'linuxvm-init:icmp-essential-v6-neighbor-solicitation' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type neighbor-advertisement -m comment --comment 'linuxvm-init:icmp-essential-v6-neighbor-advertisement' -j ACCEPT
      ;;
  esac
}

iptables_mode_delete_icmp_family() {
  local family="$1"
  case "$family" in
    ipv4)
      iptables_mode_delete_input_rule ipv4 -p icmp --icmp-type echo-request -m comment --comment 'linuxvm-init:icmp-essential-v4-echo-request' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv4 -p icmp --icmp-type destination-unreachable -m comment --comment 'linuxvm-init:icmp-essential-v4-destination-unreachable' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv4 -p icmp --icmp-type time-exceeded -m comment --comment 'linuxvm-init:icmp-essential-v4-time-exceeded' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv4 -p icmp --icmp-type parameter-problem -m comment --comment 'linuxvm-init:icmp-essential-v4-parameter-problem' -j ACCEPT || true
      ;;
    ipv6)
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type echo-request -m comment --comment 'linuxvm-init:icmp-essential-v6-echo-request' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type destination-unreachable -m comment --comment 'linuxvm-init:icmp-essential-v6-destination-unreachable' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type packet-too-big -m comment --comment 'linuxvm-init:icmp-essential-v6-packet-too-big' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type time-exceeded -m comment --comment 'linuxvm-init:icmp-essential-v6-time-exceeded' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type parameter-problem -m comment --comment 'linuxvm-init:icmp-essential-v6-parameter-problem' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type router-solicitation -m comment --comment 'linuxvm-init:icmp-essential-v6-router-solicitation' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type router-advertisement -m comment --comment 'linuxvm-init:icmp-essential-v6-router-advertisement' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type neighbor-solicitation -m comment --comment 'linuxvm-init:icmp-essential-v6-neighbor-solicitation' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type neighbor-advertisement -m comment --comment 'linuxvm-init:icmp-essential-v6-neighbor-advertisement' -j ACCEPT || true
      ;;
  esac
}

iptables_mode_allow_rule() {
  local protocol="$1"
  local value="${2:-}"
  local stack
  stack="$(network_stack_refresh)"
  case "$protocol" in
    tcp)
      iptables_mode_add_tcp_port "$value" "$stack" || return 1
      nftables_state_add_port "$value"
      ;;
    udp)
      iptables_mode_add_udp_port "$value" "$stack" || return 1
      nftables_state_add_udp_port "$value"
      ;;
    icmp)
      iptables_mode_for_each_enabled_family "$stack" iptables_mode_add_icmp_family || return 1
      state_set 'FIREWALL_ICMP_MODE' 'essential'
      state_set 'FIREWALL_ALLOW_ICMP' '1'
      ;;
    *) return 1 ;;
  esac
  state_set 'FIREWALL_MODE' 'iptables'
  iptables_mode_persist_rules "$stack"
}

iptables_mode_remove_rule() {
  local protocol="$1"
  local value="${2:-}"
  local stack
  stack="$(network_stack_refresh)"
  case "$protocol" in
    tcp)
      iptables_mode_delete_tcp_port "$value" "$stack" || return 1
      nftables_state_remove_port "$value"
      ;;
    udp)
      iptables_mode_delete_udp_port "$value" "$stack" || return 1
      nftables_state_remove_udp_port "$value"
      ;;
    icmp)
      iptables_mode_for_each_enabled_family "$stack" iptables_mode_delete_icmp_family || return 1
      state_set 'FIREWALL_ICMP_MODE' 'off'
      state_set 'FIREWALL_ALLOW_ICMP' '0'
      ;;
    *) return 1 ;;
  esac
  state_set 'FIREWALL_MODE' 'iptables'
  iptables_mode_persist_rules "$stack"
}
