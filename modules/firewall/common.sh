#!/usr/bin/env bash

# shellcheck disable=SC2034
NFTABLES_TABLE='linuxvm_init'
# shellcheck disable=SC2034
NFTABLES_FAMILY='inet'
# shellcheck disable=SC2034
NFTABLES_CONF='/etc/nftables.conf'
# shellcheck disable=SC2034
NFTABLES_LEGACY_BACKUP_ROOT='/etc/linuxvm-init/legacy-firewall-backups'

detect_ssh_port_for_firewall() {
  local ssh_port
  ssh_port="$(effective_ssh_port)"
  if ! is_valid_port "$ssh_port"; then
    say '检测 SSH 端口失败，已取消防火墙设置。' 'Failed to detect SSH port, firewall setup canceled.'
    return 1
  fi

  if is_port_in_use "$ssh_port"; then
    say "已检测到 SSH 端口: ${ssh_port}" "Detected SSH port: ${ssh_port}"
  else
    say "检测到 SSH 端口: ${ssh_port}（当前监听未确认，请谨慎）" "Detected SSH port: ${ssh_port} (listener not confirmed, proceed carefully)"
  fi
  # shellcheck disable=SC2034
  FIREWALL_SSH_PORT="$ssh_port"
  state_set 'FIREWALL_SSH_PORT' "$ssh_port"
}

nftables_install() {
  if is_installed nft; then
    return 0
  fi

  say '未检测到 nftables，正在安装。' 'nftables not found, installing.'
  run_cmd 'DEBIAN_FRONTEND=noninteractive apt install -y nftables'
}

nftables_normalize_port_list() {
  local raw="$1"
  local port normalized=''
  for port in $(printf '%s' "$raw" | tr ',' ' '); do
    if is_valid_port "$port" && ! printf ',%s,' "$normalized" | grep -q ",${port},"; then
      normalized="${normalized}${normalized:+,}${port}"
    fi
  done
  printf '%s\n' "$normalized"
}

nftables_allowed_ports() {
  nftables_normalize_port_list "$(state_get 'FIREWALL_ALLOWED_TCP_PORTS')"
}

nftables_allowed_udp_ports() {
  nftables_normalize_port_list "$(state_get 'FIREWALL_ALLOWED_UDP_PORTS')"
}

nftables_icmp_allowed() {
  [ "$(nftables_icmp_mode)" != 'off' ]
}

nftables_icmp_mode_normalize() {
  local mode="${1:-}"
  case "$mode" in
    1|essential) printf '%s\n' 'essential' ;;
    all) printf '%s\n' 'all' ;;
    0|off|'') printf '%s\n' 'off' ;;
    *) printf '%s\n' 'off' ;;
  esac
}

nftables_icmp_mode() {
  local mode legacy
  mode="$(state_get 'FIREWALL_ICMP_MODE')"
  if [ -n "$mode" ]; then
    nftables_icmp_mode_normalize "$mode"
    return
  fi

  legacy="$(state_get 'FIREWALL_ALLOW_ICMP')"
  if [ "$legacy" = '1' ]; then
    printf '%s\n' 'essential'
  else
    printf '%s\n' 'off'
  fi
}

nftables_forward_mode_normalize() {
  local mode="${1:-}"
  case "$mode" in
    strict) printf '%s\n' 'strict' ;;
    docker|'') printf '%s\n' 'docker' ;;
    *) printf '%s\n' 'docker' ;;
  esac
}

nftables_forward_mode() {
  nftables_forward_mode_normalize "$(state_get 'FIREWALL_FORWARD_MODE')"
}
nftables_setup_icmp_mode() {
  local mode legacy
  mode="$(state_get 'FIREWALL_ICMP_MODE')"
  if [ -n "$mode" ]; then
    nftables_icmp_mode_normalize "$mode"
    return
  fi

  legacy="$(state_get 'FIREWALL_ALLOW_ICMP')"
  if [ -n "$legacy" ]; then
    nftables_icmp_mode_normalize "$legacy"
  else
    printf '%s\n' 'essential'
  fi
}
nftables_state_add_port() {
  local port="$1"
  local ports
  ports="$(nftables_allowed_ports)"
  ports="$(nftables_normalize_port_list "${ports}${ports:+,}${port}")"
  state_set 'FIREWALL_ALLOWED_TCP_PORTS' "$ports"
}

nftables_state_add_udp_port() {
  local port="$1"
  local ports
  ports="$(nftables_allowed_udp_ports)"
  ports="$(nftables_normalize_port_list "${ports}${ports:+,}${port}")"
  state_set 'FIREWALL_ALLOWED_UDP_PORTS' "$ports"
}

nftables_state_remove_port() {
  local remove_port="$1"
  local port ports=''
  for port in $(printf '%s' "$(nftables_allowed_ports)" | tr ',' ' '); do
    if [ "$port" != "$remove_port" ]; then
      ports="${ports}${ports:+,}${port}"
    fi
  done
  state_set 'FIREWALL_ALLOWED_TCP_PORTS' "$ports"
}

nftables_state_remove_udp_port() {
  local remove_port="$1"
  local port ports=''
  for port in $(printf '%s' "$(nftables_allowed_udp_ports)" | tr ',' ' '); do
    if [ "$port" != "$remove_port" ]; then
      ports="${ports}${ports:+,}${port}"
    fi
  done
  state_set 'FIREWALL_ALLOWED_UDP_PORTS' "$ports"
}
nftables_current_ssh_port() {
  local ssh_port
  ssh_port="$(state_get 'FIREWALL_SSH_PORT')"
  if ! is_valid_port "$ssh_port"; then
    ssh_port="$(effective_ssh_port)"
  fi
  if is_valid_port "$ssh_port"; then
    printf '%s\n' "$ssh_port"
  else
    printf '%s\n' ''
  fi
}
