#!/usr/bin/env bash

init_summary() {
  : >"$SUMMARY_FILE"
}

record_step() {
  local name="$1"
  local status="$2"
  printf '%s|%s\n' "$name" "$status" >>"$SUMMARY_FILE"
}

print_summary() {
  if [ ! -s "$SUMMARY_FILE" ]; then
    say '本次未执行任何步骤。' 'No steps were executed in this run.'
    return
  fi
  say '==== 执行结果汇总 ====' '==== Execution Summary ===='
  while IFS='|' read -r name status; do
    if [ "$LANG_CHOICE" = 'zh' ]; then
      case "$status" in
        success) printf '[成功] %s\n' "$name" ;;
        skipped) printf '[跳过] %s\n' "$name" ;;
        failed) printf '[失败] %s\n' "$name" ;;
        *) printf '[未知] %s\n' "$name" ;;
      esac
    else
      case "$status" in
        success) printf '[OK] %s\n' "$name" ;;
        skipped) printf '[SKIP] %s\n' "$name" ;;
        failed) printf '[FAIL] %s\n' "$name" ;;
        *) printf '[UNKNOWN] %s\n' "$name" ;;
      esac
    fi
  done <"$SUMMARY_FILE"
}

print_rollback_hints() {
  say '==== 常见回滚提示 ====' '==== Common Rollback Hints ===='
  say 'SSH 配置回滚：cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config && systemctl restart sshd || systemctl restart ssh' 'SSH rollback: cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config && systemctl restart sshd || systemctl restart ssh'
  say 'Docker 配置回滚：cp /etc/docker/daemon.json.bak /etc/docker/daemon.json && systemctl restart docker' 'Docker rollback: cp /etc/docker/daemon.json.bak /etc/docker/daemon.json && systemctl restart docker'
  say '查看防火墙：ufw status numbered（手动删除错误规则）' 'Check firewall: ufw status numbered (delete wrong rules manually)'
  say 'iptables 回滚：iptables-restore < /etc/iptables/rules.v4.bak && netfilter-persistent save' 'iptables rollback: iptables-restore < /etc/iptables/rules.v4.bak && netfilter-persistent save'
  say 'Swap 回滚：swapoff /root/swapfile && rm -f /root/swapfile（并手动清理 /etc/fstab）' 'Swap rollback: swapoff /root/swapfile && rm -f /root/swapfile (clean /etc/fstab manually)'
}

ensure_state_dirs() {
  mkdir -p "$STATE_DIR"
  mkdir -p "$SNAPSHOT_DIR"
}

state_set() {
  local key="$1"
  local value="$2"
  ensure_state_dirs
  touch "$STATE_FILE"
  if grep -qE "^${key}=" "$STATE_FILE"; then
    sed -i -E "s|^${key}=.*|${key}=${value}|" "$STATE_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >>"$STATE_FILE"
  fi
}

state_get() {
  local key="$1"
  if [ -f "$STATE_FILE" ]; then
    awk -F= -v k="$key" '$1==k{print $2; exit}' "$STATE_FILE"
  fi
}
