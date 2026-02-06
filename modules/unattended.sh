#!/usr/bin/env bash

set_auto_upgrades() {
  local enabled="$1"
  mkdir -p /etc/apt/apt.conf.d
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "${enabled}";
EOF
}

unattended_enable() {
  say '风险提示：自动更新可能会在后台重启服务。' 'Warning: automatic updates may restart services in background.'
  if ! confirm '是否启用 unattended-upgrades？[y/N]' 'Enable unattended-upgrades? [y/N]'; then
    return 2
  fi
  run_cmd 'apt install -y unattended-upgrades'
  run_cmd 'DEBIAN_FRONTEND=noninteractive dpkg-reconfigure unattended-upgrades'
}

unattended_manage() {
  while true; do
    say '==== 自动安全更新管理 ====' '==== Unattended Upgrades Management ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 启用自动安全更新'
      printf '%s\n' '2) 关闭自动安全更新'
      printf '%s\n' '3) 查看服务状态'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) Enable unattended upgrades'
      printf '%s\n' '2) Disable unattended upgrades'
      printf '%s\n' '3) Show service status'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1)
        run_cmd 'apt install -y unattended-upgrades'
        set_auto_upgrades '1'
        ;;
      2)
        set_auto_upgrades '0'
        ;;
      3) run_cmd 'systemctl status unattended-upgrades --no-pager -l 2>/dev/null || true' ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
