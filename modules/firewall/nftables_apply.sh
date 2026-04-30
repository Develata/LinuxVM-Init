#!/usr/bin/env bash

nftables_validate_ruleset() {
  local rules_file="$1"
  run_argv nft -c -f "$rules_file"
}

nftables_verify_ssh_rule() {
  local ssh_port="$1"
  nft list chain "$NFTABLES_FAMILY" "$NFTABLES_TABLE" input 2>/dev/null | grep -Eq "tcp dport ${ssh_port} .*accept"
}

nftables_restore_managed_table() {
  local table_backup="$1"
  local had_table="$2"

  say '尝试恢复上一份脚本管理的 nftables 表。' 'Trying to restore the previous managed nftables table.'
  nft delete table "$NFTABLES_FAMILY" "$NFTABLES_TABLE" >/dev/null 2>&1 || true
  if [ "$had_table" = '1' ] && [ -s "$table_backup" ]; then
    if nft -f "$table_backup" >/dev/null 2>&1; then
      say '已恢复上一份 nftables 管理表。' 'Restored the previous managed nftables table.'
      return 0
    fi
    say '恢复上一份 nftables 管理表失败，请检查快照或备份。' 'Failed to restore the previous managed nftables table; inspect snapshots or backups.'
    return 1
  fi
  return 0
}

nftables_apply_ruleset_file() {
  local rules_file="$1"
  local ssh_port="$2"
  local previous_table previous_conf had_table had_conf rc
  previous_table="$(mktemp /tmp/linuxvm-init-nftables-prev-table.XXXXXX)" || return 1
  previous_conf="$(mktemp /tmp/linuxvm-init-nftables-prev-conf.XXXXXX)" || {
    rm -f "$previous_table"
    return 1
  }
  had_table='0'
  had_conf='0'

  nftables_validate_ruleset "$rules_file" || {
    rm -f "$previous_table" "$previous_conf"
    return 1
  }
  if nft list table "$NFTABLES_FAMILY" "$NFTABLES_TABLE" >"$previous_table" 2>/dev/null; then
    had_table='1'
  fi
  if [ -f "$NFTABLES_CONF" ]; then
    cp -p "$NFTABLES_CONF" "$previous_conf"
    had_conf='1'
  fi
  backup_file "$NFTABLES_CONF"
  mkdir -p "$(dirname "$NFTABLES_CONF")"
  cp "$rules_file" "$NFTABLES_CONF"

  if nft list table "$NFTABLES_FAMILY" "$NFTABLES_TABLE" >/dev/null 2>&1; then
    if ! run_argv nft delete table "$NFTABLES_FAMILY" "$NFTABLES_TABLE"; then
      if [ "$had_conf" = '1' ]; then
        cp -p "$previous_conf" "$NFTABLES_CONF"
      else
        rm -f "$NFTABLES_CONF"
      fi
      rm -f "$previous_table" "$previous_conf"
      return 1
    fi
  fi
  run_argv nft -f "$NFTABLES_CONF"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$had_conf" = '1' ]; then
      cp -p "$previous_conf" "$NFTABLES_CONF"
    else
      rm -f "$NFTABLES_CONF"
    fi
    nftables_restore_managed_table "$previous_table" "$had_table"
    rm -f "$previous_table" "$previous_conf"
    return "$rc"
  fi

  if ! nftables_verify_ssh_rule "$ssh_port"; then
    say '未能确认 SSH 端口放行规则，防火墙应用失败。' 'Could not verify the SSH allow rule, firewall apply failed.'
    if [ "$had_conf" = '1' ]; then
      cp -p "$previous_conf" "$NFTABLES_CONF"
    else
      rm -f "$NFTABLES_CONF"
    fi
    nftables_restore_managed_table "$previous_table" "$had_table"
    rm -f "$previous_table" "$previous_conf"
    return 1
  fi
  run_cmd 'systemctl enable nftables 2>/dev/null || true'

  state_set 'FIREWALL_MODE' 'nftables'
  state_set 'FIREWALL_SSH_PORT' "$ssh_port"
  nftables_warn_external_rules
  say "nftables 已应用，并已放行 SSH 端口 ${ssh_port}。" "nftables applied and SSH port ${ssh_port} is allowed."
  rm -f "$previous_table" "$previous_conf"
}

nftables_write_and_apply() {
  local ssh_port="$1"
  local source_ip="${2:-}"
  local allowed_tcp_ports="${3:-}"
  local allowed_udp_ports="${4:-}"
  local icmp_mode="${5:-off}"
  local forward_mode="${6:-docker}"
  local network_stack="${7:-unknown}"
  local tmp_file rc

  tmp_file="$(mktemp /tmp/linuxvm-init-nftables.XXXXXX)" || return 1
  nftables_render_ruleset "$tmp_file" "$ssh_port" "$source_ip" "$allowed_tcp_ports" "$allowed_udp_ports" "$icmp_mode" "$forward_mode" "$network_stack" || {
    rm -f "$tmp_file"
    return 1
  }
  nftables_apply_ruleset_file "$tmp_file" "$ssh_port"
  rc=$?
  rm -f "$tmp_file"
  return "$rc"
}
nftables_apply_current_state() {
  local ssh_port source_ip tcp_ports udp_ports icmp_mode forward_mode network_stack
  nftables_install || return 1
  network_stack="$(network_stack_refresh)"
  ssh_port="$(nftables_current_ssh_port)"
  if ! is_valid_port "$ssh_port"; then
    say '检测 SSH 端口失败，拒绝应用 nftables。' 'Failed to detect SSH port, refusing to apply nftables.'
    return 1
  fi
  source_ip="$(state_get 'FIREWALL_SSH_SOURCE_IP')"
  tcp_ports="$(nftables_allowed_ports)"
  udp_ports="$(nftables_allowed_udp_ports)"
  icmp_mode="$(nftables_icmp_mode)"
  forward_mode="$(nftables_forward_mode)"
  state_set 'FIREWALL_ICMP_MODE' "$icmp_mode"
  state_set 'FIREWALL_FORWARD_MODE' "$forward_mode"
  nftables_write_and_apply "$ssh_port" "$source_ip" "$tcp_ports" "$udp_ports" "$icmp_mode" "$forward_mode" "$network_stack"
}
