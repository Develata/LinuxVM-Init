#!/usr/bin/env bash

protocol_allow_ssh_ufw() {
  local port="$1"
  run_cmd "ufw allow $port"
}

protocol_allow_ssh_ufw_from_ip() {
  local port="$1"
  local source_ip="$2"
  run_cmd "ufw allow from $source_ip to any port $port proto tcp"
}

protocol_allow_ssh_iptables() {
  local port="$1"
  iptables_allow_port "$port"
}

protocol_allow_ssh_iptables_from_ip() {
  local port="$1"
  local source_ip="$2"
  run_cmd "iptables -I INPUT 1 -p tcp -s $source_ip --dport $port -j ACCEPT"
}
