#!/usr/bin/env bash

fail2ban_setup() {
  say '风险提示：失败登录过多会封禁你的 IP。' 'Warning: too many failed logins can ban your IP.'
  if ! confirm '是否安装并配置 fail2ban？[y/N]' 'Install and configure fail2ban? [y/N]'; then
    return 2
  fi
  local f2b_port
  f2b_port="$(effective_ssh_port)"
  run_cmd 'apt install -y fail2ban'
  cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
backend = systemd
port = ${f2b_port}
filter = sshd
maxretry = 10
findtime = 300
bantime = 86400
EOF
  run_cmd 'systemctl restart fail2ban'
  run_cmd 'systemctl enable fail2ban'
  run_cmd 'fail2ban-client status sshd'
}
