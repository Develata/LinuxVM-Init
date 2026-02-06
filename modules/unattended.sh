#!/usr/bin/env bash

unattended_enable() {
  say '风险提示：自动更新可能会在后台重启服务。' 'Warning: automatic updates may restart services in background.'
  if ! confirm '是否启用 unattended-upgrades？[y/N]' 'Enable unattended-upgrades? [y/N]'; then
    return 2
  fi
  run_cmd 'apt install -y unattended-upgrades'
  run_cmd 'DEBIAN_FRONTEND=noninteractive dpkg-reconfigure unattended-upgrades'
}
