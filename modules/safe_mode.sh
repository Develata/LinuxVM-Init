#!/usr/bin/env bash

novice_safe_repair() {
  say '新手安全修复会尽量保证可登录与基础防护。' 'Safe repair tries to preserve access and baseline security.'
  say '将执行：快照、SSH端口放行、防火墙修复、fail2ban修复。' 'Will do: snapshot, SSH allow rule, firewall fix, fail2ban fix.'
  if ! confirm '确认执行新手一键修复？[y/N]' 'Run novice one-click safe repair? [y/N]'; then
    return 2
  fi

  snapshot_create 'before-novice-safe-repair'
  detect_ssh_port_for_firewall || return 1

  local src_ip
  src_ip="$(detect_source_ip)"

  nftables_install || return 1
  network_stack_refresh >/dev/null
  if nftables_legacy_firewall_detected; then
    nftables_backup_legacy_firewalls
    nftables_disable_legacy_firewalls
  fi
  state_set 'FIREWALL_MODE' 'nftables'
  state_set 'FIREWALL_SSH_PORT' "$FIREWALL_SSH_PORT"
  state_set 'FIREWALL_SSH_SOURCE_IP' "$src_ip"
  state_set 'FIREWALL_ICMP_MODE' "$(nftables_setup_icmp_mode)"
  state_set 'FIREWALL_FORWARD_MODE' 'docker'
  nftables_apply_current_state || return 1

  backup_file '/etc/ssh/sshd_config'
  set_sshd_option 'Port' "$FIREWALL_SSH_PORT"
  set_sshd_option 'PubkeyAuthentication' 'yes'
  apply_sshd_changes || return 1

  run_cmd 'apt install -y fail2ban'
  write_fail2ban_jail "$FIREWALL_SSH_PORT" '10' '300' '86400' "$src_ip"
  run_cmd 'systemctl restart fail2ban'
  run_cmd 'systemctl enable fail2ban'
  run_cmd 'fail2ban-client status sshd'

  print_ssh_test_hint
  say '新手一键修复完成。' 'Novice one-click safe repair completed.'
}
