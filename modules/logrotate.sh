#!/usr/bin/env bash

logrotate_setup() {
  say '风险提示：日志切割配置错误可能导致日志过快删除。' 'Warning: misconfigured logrotate may delete logs too quickly.'
  if ! confirm '是否安装并配置 logrotate？[y/N]' 'Install and configure logrotate? [y/N]'; then
    return 2
  fi
  run_cmd 'apt install -y logrotate cron'
  cat > /etc/logrotate.d/vps-init-system <<EOF
/var/log/syslog
/var/log/mail.log
/var/log/kern.log
/var/log/auth.log
/var/log/user.log
/var/log/cron.log
{
  weekly
  rotate 3
  maxsize 100M
  missingok
  notifempty
  compress
  delaycompress
  sharedscripts
  postrotate
    /usr/lib/rsyslog/rsyslog-rotate
  endscript
}
EOF
  say 'logrotate 配置完成。' 'logrotate configuration completed.'
}
