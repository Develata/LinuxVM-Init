#!/usr/bin/env bash

write_fail2ban_jail() {
  local port="$1"
  local maxretry="$2"
  local findtime="$3"
  local bantime="$4"
  local source_ip="$5"
  local ignore_list='127.0.0.1/8'
  if [ -n "$source_ip" ]; then
    ignore_list="$ignore_list $source_ip"
  fi
  cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = ${ignore_list}

[sshd]
enabled = true
backend = systemd
port = ${port}
filter = sshd
maxretry = ${maxretry}
findtime = ${findtime}
bantime = ${bantime}
EOF
}

fail2ban_setup() {
  say '风险提示：失败登录过多会封禁你的 IP。' 'Warning: too many failed logins can ban your IP.'
  if ! confirm '是否安装并配置 fail2ban？[y/N]' 'Install and configure fail2ban? [y/N]'; then
    return 2
  fi
  local f2b_port
  local maxretry='10'
  local findtime='300'
  local bantime='86400'
  local source_ip
  f2b_port="$(effective_ssh_port)"
  source_ip="$(detect_source_ip)"

  ask '最大重试次数(默认10)：' 'Max retry (default 10):' in_maxretry
  if [[ "$in_maxretry" =~ ^[0-9]+$ ]] && [ "$in_maxretry" -gt 0 ]; then
    maxretry="$in_maxretry"
  fi
  ask '统计窗口秒数(默认300)：' 'Findtime seconds (default 300):' in_findtime
  if [[ "$in_findtime" =~ ^[0-9]+$ ]] && [ "$in_findtime" -gt 0 ]; then
    findtime="$in_findtime"
  fi
  ask '封禁时长秒数(默认86400)：' 'Bantime seconds (default 86400):' in_bantime
  if [[ "$in_bantime" =~ ^-?[0-9]+$ ]]; then
    bantime="$in_bantime"
  fi

  run_cmd 'apt install -y fail2ban'
  snapshot_create 'before-fail2ban-setup'
  write_fail2ban_jail "$f2b_port" "$maxretry" "$findtime" "$bantime" "$source_ip"
  run_cmd 'systemctl restart fail2ban'
  run_cmd 'systemctl enable fail2ban'
  run_cmd 'fail2ban-client status sshd'
}
