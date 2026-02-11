#!/usr/bin/env bash

novice_safe_repair() {
  say '新手安全修复会尽量保证可登录与基础防护。' 'Safe repair tries to preserve access and baseline security.'
  say '将执行：快照、SSH端口放行、防火墙修复、fail2ban修复。' 'Will do: snapshot, SSH allow rule, firewall fix, fail2ban fix.'
  if ! confirm '确认执行新手一键修复？[y/N]' 'Run novice one-click safe repair? [y/N]'; then
    return 2
  fi

  snapshot_create 'before-novice-safe-repair'
  detect_ssh_port_for_firewall || return 1

  local src_ip fw_mode
  src_ip="$(detect_source_ip)"
  fw_mode="$(state_get 'FIREWALL_MODE')"

  if [ "$fw_mode" = 'iptables' ] && is_installed iptables; then
    run_cmd 'DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent'
    iptables_ensure_base_rules
    [ -n "$src_ip" ] && protocol_allow_ssh_iptables_from_ip "$FIREWALL_SSH_PORT" "$src_ip"
    protocol_allow_ssh_iptables "$FIREWALL_SSH_PORT"
    run_cmd 'iptables -P INPUT DROP'
    run_cmd 'iptables -P FORWARD DROP'
    run_cmd 'iptables -P OUTPUT ACCEPT'
    run_cmd 'iptables-save > /etc/iptables/rules.v4'
    run_cmd 'netfilter-persistent save'
    run_cmd 'netfilter-persistent reload'
  else
    if ! is_installed ufw; then
      run_cmd 'apt install -y ufw'
    fi
    protocol_allow_ssh_ufw "$FIREWALL_SSH_PORT"
    [ -n "$src_ip" ] && protocol_allow_ssh_ufw_from_ip "$FIREWALL_SSH_PORT" "$src_ip"
    run_cmd 'ufw --force enable'
    state_set 'FIREWALL_MODE' 'ufw'
  fi

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
