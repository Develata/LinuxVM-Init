#!/usr/bin/env bash

SNAPSHOT_RETENTION_DAYS='14'

snapshot_cleanup_old() {
  ensure_state_dirs
  local removed_count
  removed_count="$(find "$SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +13 -print 2>/dev/null | wc -l)"
  if [ "$removed_count" -gt 0 ]; then
    find "$SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +13 -exec rm -rf {} + 2>/dev/null
    say "已自动清理 ${removed_count} 个超过 ${SNAPSHOT_RETENTION_DAYS} 天的快照。" "Auto-cleaned ${removed_count} snapshots older than ${SNAPSHOT_RETENTION_DAYS} days."
  fi
}

snapshot_create() {
  local reason="$1"
  ensure_state_dirs
  local ts dir
  ts="$(date +%Y%m%d-%H%M%S)"
  dir="$SNAPSHOT_DIR/$ts"
  mkdir -p "$dir"

  [ -f /etc/ssh/sshd_config ] && cp /etc/ssh/sshd_config "$dir/sshd_config"
  [ -f /etc/fail2ban/jail.local ] && cp /etc/fail2ban/jail.local "$dir/jail.local"
  [ -f /etc/iptables/rules.v4 ] && cp /etc/iptables/rules.v4 "$dir/rules.v4"
  [ -f /etc/iptables/rules.v6 ] && cp /etc/iptables/rules.v6 "$dir/rules.v6"
  [ -f /etc/ufw/user.rules ] && cp /etc/ufw/user.rules "$dir/ufw_user.rules"
  [ -f /etc/ufw/user6.rules ] && cp /etc/ufw/user6.rules "$dir/ufw_user6.rules"
  [ -f /etc/nftables.conf ] && cp /etc/nftables.conf "$dir/nftables.conf"
  if is_installed nft; then
    nft list ruleset >"$dir/nft-list-ruleset.txt" 2>"$dir/nft-list-ruleset.err" || true
  fi
  [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && cp /etc/apt/apt.conf.d/20auto-upgrades "$dir/20auto-upgrades"
  [ -f /etc/docker/daemon.json ] && cp /etc/docker/daemon.json "$dir/daemon.json"
  [ -f /etc/systemd/system/docker.service.d/http-proxy.conf ] && cp /etc/systemd/system/docker.service.d/http-proxy.conf "$dir/docker_http_proxy.conf"
  [ -f /etc/systemd/system/ssh.socket.d/override.conf ] && cp /etc/systemd/system/ssh.socket.d/override.conf "$dir/ssh_socket_override.conf"
  [ -f /etc/systemd/system/ssh.socket.d/override.conf ] || touch "$dir/ssh_socket_override.absent"
  [ -f /etc/fstab ] && cp /etc/fstab "$dir/fstab"
  [ -f "$STATE_FILE" ] && cp "$STATE_FILE" "$dir/state.env"

  printf 'time=%s\nreason=%s\n' "$ts" "$reason" >"$dir/meta"
  state_set 'LAST_SNAPSHOT' "$ts"
  snapshot_cleanup_old
  say "已创建快照：$ts" "Snapshot created: $ts"
}

snapshot_list() {
  ensure_state_dirs
  say '==== 快照列表 ====' '==== Snapshot List ===='
  ls -1 "$SNAPSHOT_DIR" 2>/dev/null || true
}

snapshot_restore_by_id() {
  local sid="$1"
  local dir="$SNAPSHOT_DIR/$sid"
  if ! [[ "$sid" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
    say '快照 ID 格式无效。' 'Invalid snapshot ID format.'
    return 1
  fi
  if [ ! -d "$dir" ]; then
    say '快照不存在。' 'Snapshot not found.'
    return 1
  fi
  say "风险提示：将回滚系统配置到快照 $sid" "Warning: system configs will be restored to snapshot $sid"
  if ! confirm '确认回滚？[y/N]' 'Confirm restore? [y/N]'; then
    return 2
  fi

  [ -f "$dir/sshd_config" ] && mkdir -p /etc/ssh && cp "$dir/sshd_config" /etc/ssh/sshd_config
  [ -f "$dir/jail.local" ] && mkdir -p /etc/fail2ban && cp "$dir/jail.local" /etc/fail2ban/jail.local
  [ -f "$dir/rules.v4" ] && mkdir -p /etc/iptables && cp "$dir/rules.v4" /etc/iptables/rules.v4
  [ -f "$dir/rules.v6" ] && mkdir -p /etc/iptables && cp "$dir/rules.v6" /etc/iptables/rules.v6
  [ -f "$dir/ufw_user.rules" ] && mkdir -p /etc/ufw && cp "$dir/ufw_user.rules" /etc/ufw/user.rules
  [ -f "$dir/ufw_user6.rules" ] && mkdir -p /etc/ufw && cp "$dir/ufw_user6.rules" /etc/ufw/user6.rules
  [ -f "$dir/nftables.conf" ] && cp "$dir/nftables.conf" /etc/nftables.conf
  [ -f "$dir/20auto-upgrades" ] && mkdir -p /etc/apt/apt.conf.d && cp "$dir/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades
  [ -f "$dir/daemon.json" ] && mkdir -p /etc/docker && cp "$dir/daemon.json" /etc/docker/daemon.json
  if [ -f "$dir/docker_http_proxy.conf" ]; then
    mkdir -p /etc/systemd/system/docker.service.d
    cp "$dir/docker_http_proxy.conf" /etc/systemd/system/docker.service.d/http-proxy.conf
  fi
  if [ -f "$dir/ssh_socket_override.conf" ]; then
    mkdir -p /etc/systemd/system/ssh.socket.d
    cp "$dir/ssh_socket_override.conf" /etc/systemd/system/ssh.socket.d/override.conf
  elif [ -f "$dir/ssh_socket_override.absent" ]; then
    rm -f /etc/systemd/system/ssh.socket.d/override.conf
  fi
  [ -f "$dir/fstab" ] && cp "$dir/fstab" /etc/fstab
  [ -f "$dir/state.env" ] && cp "$dir/state.env" "$STATE_FILE"

  run_cmd 'systemctl daemon-reload 2>/dev/null || true'
  run_cmd 'systemctl restart sshd 2>/dev/null || systemctl restart ssh || true'
  run_cmd 'systemctl restart ssh.socket 2>/dev/null || true'
  run_cmd 'systemctl restart fail2ban 2>/dev/null || true'
  run_cmd 'systemctl restart docker 2>/dev/null || true'
  if [ -f /etc/nftables.conf ] && is_installed nft; then
    run_cmd "nft delete table ${NFTABLES_FAMILY} ${NFTABLES_TABLE} 2>/dev/null || true"
    run_cmd 'nft -f /etc/nftables.conf'
  fi
  say '快照回滚完成。' 'Snapshot restore completed.'
}

snapshot_manage() {
  while true; do
    say '==== 快照与回滚 ====' '==== Snapshot & Restore ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 立即创建快照'
      printf '%s\n' '2) 查看快照列表'
      printf '%s\n' '3) 按快照ID回滚'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) Create snapshot now'
      printf '%s\n' '2) List snapshots'
      printf '%s\n' '3) Restore by snapshot ID'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) snapshot_create 'manual' ;;
      2) snapshot_list ;;
      3)
        snapshot_list
        ask '输入快照ID：' 'Enter snapshot ID:' sid
        [ -n "$sid" ] && snapshot_restore_by_id "$sid"
        ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
