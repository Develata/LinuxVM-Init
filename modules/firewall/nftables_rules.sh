#!/usr/bin/env bash

nftables_allow_tcp_port() {
  local port="$1"
  if ! is_valid_port "$port"; then
    say '端口无效。' 'Invalid port.'
    return 1
  fi

  nftables_state_add_port "$port"
  nftables_apply_current_state
}

nftables_remove_tcp_port() {
  local port="$1"
  local ssh_port
  if ! is_valid_port "$port"; then
    say '端口无效。' 'Invalid port.'
    return 1
  fi

  ssh_port="$(nftables_current_ssh_port)"
  if [ "$port" = "$ssh_port" ]; then
    say '拒绝删除当前 SSH 端口放行规则。' 'Refusing to remove the current SSH allow rule.'
    return 1
  fi

  nftables_state_remove_port "$port"
  nftables_apply_current_state
}

nftables_allow_udp_port() {
  local port="$1"
  if ! is_valid_port "$port"; then
    say '端口无效。' 'Invalid port.'
    return 1
  fi

  nftables_state_add_udp_port "$port"
  nftables_apply_current_state
}

nftables_remove_udp_port() {
  local port="$1"
  if ! is_valid_port "$port"; then
    say '端口无效。' 'Invalid port.'
    return 1
  fi

  nftables_state_remove_udp_port "$port"
  nftables_apply_current_state
}

nftables_allow_icmp() {
  state_set 'FIREWALL_ICMP_MODE' 'essential'
  state_set 'FIREWALL_ALLOW_ICMP' '1'
  nftables_apply_current_state
}

nftables_remove_icmp() {
  state_set 'FIREWALL_ICMP_MODE' 'off'
  state_set 'FIREWALL_ALLOW_ICMP' '0'
  nftables_apply_current_state
}

nftables_allow_rule() {
  local protocol="$1"
  local value="${2:-}"
  protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
  case "$protocol" in
    tcp) nftables_allow_tcp_port "$value" ;;
    udp) nftables_allow_udp_port "$value" ;;
    icmp) nftables_allow_icmp ;;
    *)
      say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
      return 1
      ;;
  esac
}

nftables_remove_rule() {
  local protocol="$1"
  local value="${2:-}"
  protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
  case "$protocol" in
    tcp) nftables_remove_tcp_port "$value" ;;
    udp) nftables_remove_udp_port "$value" ;;
    icmp) nftables_remove_icmp ;;
    *)
      say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
      return 1
      ;;
  esac
}

firewall_can_modify_current_rules() {
  case "$(firewall_effective_mode)" in
    iptables)
      is_installed iptables || is_installed ip6tables
      ;;
    nftables)
      nftables_managed_active
      ;;
    *)
      return 1
      ;;
  esac
}

firewall_allow_rule() {
  local protocol="$1"
  local value="${2:-}"
  protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
  case "$protocol" in
    tcp|udp)
      if ! is_valid_port "$value"; then
        say '端口无效。' 'Invalid port.'
        return 1
      fi
      ;;
    icmp)
      value=''
      ;;
    *)
      say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
      return 1
      ;;
  esac

  case "$(firewall_effective_mode)" in
    iptables) iptables_mode_allow_rule "$protocol" "$value" ;;
    nftables) nftables_allow_rule "$protocol" "$value" ;;
    *) return 1 ;;
  esac
}

firewall_remove_rule() {
  local protocol="$1"
  local value="${2:-}"
  local ssh_port
  protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
  case "$protocol" in
    tcp|udp)
      if ! is_valid_port "$value"; then
        say '端口无效。' 'Invalid port.'
        return 1
      fi
      ;;
    icmp)
      value=''
      ;;
    *)
      say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
      return 1
      ;;
  esac

  if [ "$protocol" = 'tcp' ]; then
    ssh_port="$(nftables_current_ssh_port)"
    if [ "$value" = "$ssh_port" ]; then
      say '拒绝删除当前 SSH 端口放行规则。' 'Refusing to remove the current SSH allow rule.'
      return 1
    fi
  fi

  case "$(firewall_effective_mode)" in
    iptables) iptables_mode_remove_rule "$protocol" "$value" ;;
    nftables) nftables_remove_rule "$protocol" "$value" ;;
    *) return 1 ;;
  esac
}

nftables_allow_ssh_port() {
  local port="$1"
  if ! is_valid_port "$port"; then
    say 'SSH 端口无效。' 'Invalid SSH port.'
    return 1
  fi

  state_set 'FIREWALL_SSH_PORT' "$port"
  if nftables_managed_active; then
    nftables_apply_current_state
  elif nftables_legacy_firewall_detected; then
    say '检测到旧防火墙可能阻断新 SSH 端口。请先在防火墙面板切换到 nftables，再修改 SSH 端口。' 'A legacy firewall may block the new SSH port. Switch to nftables in the firewall panel before changing the SSH port.'
    return 1
  else
    say 'nftables 尚未由本脚本启用，已记录 SSH 端口，防火墙初始化时会放行。' 'nftables is not managed by this script yet; SSH port recorded and will be allowed during firewall setup.'
  fi
}

nftables_allow_ssh_from_ip() {
  local port="$1"
  local source_ip="$2"
  if ! is_valid_port "$port" || ! is_valid_ip "$source_ip"; then
    say 'SSH 来源 IP 或端口无效。' 'Invalid SSH source IP or port.'
    return 1
  fi

  state_set 'FIREWALL_SSH_PORT' "$port"
  state_set 'FIREWALL_SSH_SOURCE_IP' "$source_ip"
  if nftables_managed_active; then
    nftables_apply_current_state
  fi
}

apply_source_ip_whitelist_firewall() {
  local source_ip
  source_ip="$(detect_source_ip)"
  FIREWALL_SOURCE_IP=''
  if [ -z "$source_ip" ]; then
    say '未检测到来源 IP，跳过来源 IP 白名单保护。' 'Source IP not detected, skipping source whitelist protection.'
    return 0
  fi

  say "来源 IP 白名单保护：$source_ip" "Source IP whitelist protection: $source_ip"
  # shellcheck disable=SC2034
  FIREWALL_SOURCE_IP="$source_ip"
}
