#!/usr/bin/env bash

protocol_allow_ssh_ufw() {
  local port="$1"
  run_argv ufw allow "${port}/tcp"
}

protocol_allow_ssh_ufw_from_ip() {
  local port="$1"
  local source_ip="$2"
  run_argv ufw allow from "$source_ip" to any port "$port" proto tcp
}

protocol_allow_ssh_iptables() {
  local port="$1"
  iptables_allow_port "$port"
}

protocol_allow_ssh_iptables_from_ip() {
  local port="$1"
  local source_ip="$2"
  if [[ "$source_ip" =~ : ]]; then
    if ! is_installed ip6tables; then
      say '未检测到 ip6tables，跳过 IPv6 来源 IP 白名单。' 'ip6tables not found, skipping IPv6 source whitelist.'
      return 0
    fi
    run_argv ip6tables -I INPUT 1 -p tcp -s "$source_ip" --dport "$port" -j ACCEPT
  else
    run_argv iptables -I INPUT 1 -p tcp -s "$source_ip" --dport "$port" -j ACCEPT
  fi
}
