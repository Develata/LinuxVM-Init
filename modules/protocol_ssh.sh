#!/usr/bin/env bash

protocol_allow_ssh_nftables() {
  local port="$1"
  nftables_allow_ssh_port "$port"
}

protocol_allow_ssh_nftables_from_ip() {
  local port="$1"
  local source_ip="$2"
  nftables_allow_ssh_from_ip "$port" "$source_ip"
}

protocol_allow_ssh_ufw() {
  local port="$1"
  say 'ufw 放行接口已兼容转发到 nftables。' 'ufw allow interface is now forwarded to nftables.'
  nftables_allow_ssh_port "$port"
}

protocol_allow_ssh_ufw_from_ip() {
  local port="$1"
  local source_ip="$2"
  say 'ufw 来源 IP 放行接口已兼容转发到 nftables。' 'ufw source allow interface is now forwarded to nftables.'
  nftables_allow_ssh_from_ip "$port" "$source_ip"
}

protocol_allow_ssh_iptables() {
  local port="$1"
  local stack
  say 'iptables 模式：将通过 iptables/ip6tables 放行 SSH 端口。' 'iptables mode: allowing SSH through iptables/ip6tables.'
  stack="$(network_stack_refresh)"
  iptables_mode_add_tcp_port "$port" "$stack" || return 1
  state_set 'FIREWALL_MODE' 'iptables'
  state_set 'FIREWALL_SSH_PORT' "$port"
  iptables_mode_persist_rules "$stack"
}

protocol_allow_ssh_iptables_from_ip() {
  local port="$1"
  local source_ip="$2"
  local stack
  say 'iptables 模式：将通过 iptables/ip6tables 添加 SSH 来源 IP 白名单。' 'iptables mode: adding an SSH source allow rule through iptables/ip6tables.'
  stack="$(network_stack_refresh)"
  iptables_mode_add_tcp_port_from_ip "$port" "$source_ip" "$stack" || return 1
  state_set 'FIREWALL_MODE' 'iptables'
  state_set 'FIREWALL_SSH_PORT' "$port"
  state_set 'FIREWALL_SSH_SOURCE_IP' "$source_ip"
  iptables_mode_persist_rules "$stack"
}
