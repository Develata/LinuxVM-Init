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
  [ -f /etc/ufw/user.rules ] && cp /etc/ufw/user.rules "$dir/ufw_user.rules"
  [ -f /etc/ufw/user6.rules ] && cp /etc/ufw/user6.rules "$dir/ufw_user6.rules"
  [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && cp /etc/apt/apt.conf.d/20auto-upgrades "$dir/20auto-upgrades"
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
  if [ ! -d "$dir" ]; then
    say '快照不存在。' 'Snapshot not found.'
    return 1
  fi
  say "风险提示：将回滚系统配置到快照 $sid" "Warning: system configs will be restored to snapshot $sid"
  if ! confirm '确认回滚？[y/N]' 'Confirm restore? [y/N]'; then
    return 2
  fi

  [ -f "$dir/sshd_config" ] && cp "$dir/sshd_config" /etc/ssh/sshd_config
  [ -f "$dir/jail.local" ] && cp "$dir/jail.local" /etc/fail2ban/jail.local
  [ -f "$dir/rules.v4" ] && cp "$dir/rules.v4" /etc/iptables/rules.v4
  [ -f "$dir/ufw_user.rules" ] && cp "$dir/ufw_user.rules" /etc/ufw/user.rules
  [ -f "$dir/ufw_user6.rules" ] && cp "$dir/ufw_user6.rules" /etc/ufw/user6.rules
  [ -f "$dir/20auto-upgrades" ] && cp "$dir/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades
  [ -f "$dir/state.env" ] && cp "$dir/state.env" "$STATE_FILE"

  run_cmd 'systemctl restart sshd 2>/dev/null || systemctl restart ssh || true'
  run_cmd 'systemctl restart fail2ban 2>/dev/null || true'
  run_cmd 'netfilter-persistent reload 2>/dev/null || true'
  run_cmd 'ufw reload 2>/dev/null || true'
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
