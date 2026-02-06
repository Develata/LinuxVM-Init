#!/usr/bin/env bash

system_update() {
  say '风险提示：更新可能会重启服务，短时间内影响连接。' 'Warning: updates may restart services and impact connectivity.'
  if ! confirm '继续执行系统更新？[y/N]' 'Proceed with system updates? [y/N]'; then
    return 2
  fi
  run_cmd 'apt update'
  run_cmd 'apt upgrade --only-upgrade -y'
}
