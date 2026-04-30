#!/usr/bin/env bash

nftables_setup() {
  local setup_tcp_ports
  local source_ip
  local iptables_frontend
  local network_stack
  say '风险提示：启用防火墙但未放行 SSH 端口会断开连接。' 'Warning: enabling firewall without SSH port will cut off access.'
  say '风险提示：nftables 将设置 INPUT/FORWARD 默认策略为 DROP。' 'Warning: nftables will set INPUT/FORWARD default policy to DROP.'

  nftables_install || return 1
  network_stack="$(network_stack_refresh)"
  say "检测到网络栈：${network_stack}（unknown 会按 dual 保守处理）" "Detected network stack: ${network_stack} (unknown is handled conservatively as dual)"
  iptables_frontend="$(nftables_refresh_iptables_frontend_state)"
  case "$iptables_frontend" in
    nft)
      say '检测到 iptables-nft 兼容层：它与 nftables 共用内核规则集，本脚本将继续使用 nftables 原生规则覆盖 IPv4/IPv6。' 'Detected iptables-nft compatibility layer; it shares the nftables kernel ruleset, and this script will keep using native nftables rules for IPv4/IPv6.'
      ;;
    legacy|mixed)
      say "检测到 iptables 前端状态：${iptables_frontend}。本脚本不会自动切换 alternatives；将以 nftables 原生规则为准。" "Detected iptables frontend: ${iptables_frontend}. This script will not change alternatives automatically; native nftables rules remain authoritative."
      ;;
  esac
  snapshot_create 'before-nftables-setup'

  if nftables_legacy_firewall_detected; then
    say '检测到旧防火墙配置、iptables 兼容层规则或其他 nftables 规则。切换前会先保存现有规则；iptables-nft 兼容层不会被禁用。' 'Detected legacy firewall config, iptables compatibility rules, or other nftables rules. Existing rules will be backed up first; iptables-nft compatibility will not be disabled.'
    if ! confirm '确认备份现有规则并应用 nftables？[y/N]' 'Back up existing rules and apply nftables? [y/N]'; then
      return 2
    fi
    nftables_backup_legacy_firewalls
    nftables_disable_legacy_firewalls
  fi

  detect_ssh_port_for_firewall || return 1
  say "防火墙将强制放行 SSH 端口 ${FIREWALL_SSH_PORT}" "Firewall will always allow SSH port ${FIREWALL_SSH_PORT}"
  apply_source_ip_whitelist_firewall
  source_ip="${FIREWALL_SOURCE_IP:-}"

  setup_tcp_ports="$(nftables_allowed_ports)"
  if confirm '放行 80 端口 (HTTP)？[y/N]' 'Allow port 80 (HTTP)? [y/N]'; then
    setup_tcp_ports="$(nftables_normalize_port_list "${setup_tcp_ports}${setup_tcp_ports:+,}80")"
  fi
  if confirm '放行 443 端口 (HTTPS)？[y/N]' 'Allow port 443 (HTTPS)? [y/N]'; then
    setup_tcp_ports="$(nftables_normalize_port_list "${setup_tcp_ports}${setup_tcp_ports:+,}443")"
  fi

  say "二次确认：即将放行 SSH 端口 ${FIREWALL_SSH_PORT}；ICMP=essential；FORWARD=docker；默认策略 INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT" "Final check: SSH port ${FIREWALL_SSH_PORT} will be allowed; ICMP=essential; FORWARD=docker; default policy to apply: INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT"
  if ! confirm '确认应用 nftables 防火墙？[y/N]' 'Confirm applying nftables firewall? [y/N]'; then
    return 2
  fi

  state_set 'FIREWALL_SSH_PORT' "$FIREWALL_SSH_PORT"
  state_set 'FIREWALL_SSH_SOURCE_IP' "$source_ip"
  state_set 'FIREWALL_ALLOWED_TCP_PORTS' "$setup_tcp_ports"
  state_set 'FIREWALL_ICMP_MODE' "$(nftables_setup_icmp_mode)"
  state_set 'FIREWALL_FORWARD_MODE' 'docker'
  nftables_apply_current_state || return 1
  run_cmd "nft list table ${NFTABLES_FAMILY} ${NFTABLES_TABLE}"
}

ufw_setup() {
  say 'ufw 后端已废弃，v1.0.7 起统一使用 nftables。' 'ufw backend is deprecated; v1.0.7 uses nftables only.'
  nftables_setup
}

iptables_setup() {
  say 'iptables 后端已废弃，v1.0.7 起统一使用 nftables。' 'iptables backend is deprecated; v1.0.7 uses nftables only.'
  nftables_setup
}

firewall_setup() {
  local requested_mode current_mode
  current_mode="$(state_get 'FIREWALL_MODE')"
  if [ -n "$current_mode" ]; then
    say "当前记录的防火墙模式：$current_mode" "Current recorded firewall mode: $current_mode"
  fi
  requested_mode="${NI_FIREWALL_MODE:-}"
  if [ -n "$requested_mode" ] && [ "$requested_mode" != 'nftables' ]; then
    say "NI_FIREWALL_MODE=${requested_mode} 已废弃，将统一使用 nftables。" "NI_FIREWALL_MODE=${requested_mode} is deprecated; nftables will be used."
  fi
  nftables_setup
}
