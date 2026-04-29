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
  say 'iptables 放行接口已兼容转发到 nftables。' 'iptables allow interface is now forwarded to nftables.'
  nftables_allow_ssh_port "$port"
}

protocol_allow_ssh_iptables_from_ip() {
  local port="$1"
  local source_ip="$2"
  say 'iptables 来源 IP 放行接口已兼容转发到 nftables。' 'iptables source allow interface is now forwarded to nftables.'
  nftables_allow_ssh_from_ip "$port" "$source_ip"
}
