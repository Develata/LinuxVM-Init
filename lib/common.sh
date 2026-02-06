#!/usr/bin/env bash

LANG_CHOICE='zh'
LOG_FILE='/var/log/vps-init.log'
DISTRO_ID=''
SSH_PORT=''
SUMMARY_FILE='/tmp/vps-init-summary.log'

say() {
  local zh="$1"
  local en="$2"
  if [ "$LANG_CHOICE" = 'zh' ]; then
    printf '%s\n' "$zh"
  else
    printf '%s\n' "$en"
  fi
}

confirm() {
  local zh="$1"
  local en="$2"
  local prompt
  if [ "$LANG_CHOICE" = 'zh' ]; then
    prompt="$zh"
  else
    prompt="$en"
  fi
  printf '%s ' "$prompt"
  read -r ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

ask() {
  local zh="$1"
  local en="$2"
  local var_name="$3"
  local prompt
  if [ "$LANG_CHOICE" = 'zh' ]; then
    prompt="$zh"
  else
    prompt="$en"
  fi
  printf '%s ' "$prompt"
  read -r value
  printf -v "$var_name" '%s' "$value"
}

pause() {
  say '按回车继续...' 'Press Enter to continue...'
  read -r _
}

ensure_log() {
  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE" 2>/dev/null || true
  fi
}

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
  say 'Swap 回滚：swapoff /root/swapfile && rm -f /root/swapfile（并手动清理 /etc/fstab）' 'Swap rollback: swapoff /root/swapfile && rm -f /root/swapfile (clean /etc/fstab manually)'
}

log_line() {
  printf '%s\n' "$1" >>"$LOG_FILE" 2>/dev/null || true
}

run_cmd() {
  local cmd="$1"
  printf '>> %s\n' "$cmd"
  log_line ">> $cmd"
  bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    say '请以 root 身份运行。' 'Please run as root.'
    exit 1
  fi
}

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "${file}.bak"
  fi
}

is_installed() {
  command -v "$1" >/dev/null 2>&1
}
