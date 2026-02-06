#!/usr/bin/env bash

MONITOR_SCRIPT='/usr/local/bin/linuxvm-init-daily-report.sh'
MONITOR_CRON='/etc/cron.d/linuxvm-init-daily'

monitor_write_script() {
  cat > "$MONITOR_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -u
report_dir='/var/log/linuxvm-init'
mkdir -p "$report_dir"
report_file="$report_dir/daily-$(date +%F).log"
{
  echo "=== LinuxVM-Init Daily Report $(date '+%F %T') ==="
  echo "hostname: $(hostname)"
  echo "uptime: $(uptime -p 2>/dev/null || uptime)"
  echo "load: $(uptime | awk -F'load average: ' '{print $2}')"
  echo "memory:"; free -h
  echo "disk:"; df -h /
  echo "ssh status:"; systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || true
  echo "fail2ban status:"; fail2ban-client status sshd 2>/dev/null || echo 'fail2ban not ready'
  echo "firewall mode:"; awk -F= '/^FIREWALL_MODE=/{print $2}' /etc/linuxvm-init/state.env 2>/dev/null || echo 'unknown'
  echo "firewall snapshot:"; ufw status 2>/dev/null || iptables -L -n 2>/dev/null | head -n 20 || true
  echo
} > "$report_file"
EOF
  chmod +x "$MONITOR_SCRIPT"
}

monitor_setup_daily() {
  ensure_state_dirs
  monitor_write_script
  cat > "$MONITOR_CRON" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
15 6 * * * root $MONITOR_SCRIPT
EOF
  say '每日巡检任务已启用（每天 06:15）。' 'Daily inspection scheduled at 06:15.'
}

monitor_disable_daily() {
  rm -f "$MONITOR_CRON"
  say '每日巡检任务已关闭。' 'Daily inspection disabled.'
}

monitor_run_now() {
  run_cmd "$MONITOR_SCRIPT"
  run_cmd 'ls -1t /var/log/linuxvm-init/daily-*.log 2>/dev/null | head -n 1 | xargs -r tail -n 80'
}

monitor_manage() {
  while true; do
    say '==== 巡检与每日简报 ====' '==== Inspection & Daily Report ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 启用每日巡检任务'
      printf '%s\n' '2) 关闭每日巡检任务'
      printf '%s\n' '3) 立即执行一次巡检'
      printf '%s\n' '4) 查看最近简报'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) Enable daily inspection'
      printf '%s\n' '2) Disable daily inspection'
      printf '%s\n' '3) Run inspection now'
      printf '%s\n' '4) Show latest report'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) monitor_setup_daily ;;
      2) monitor_disable_daily ;;
      3) monitor_run_now ;;
      4) run_cmd 'ls -1t /var/log/linuxvm-init/daily-*.log 2>/dev/null | head -n 1 | xargs -r tail -n 120' ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
