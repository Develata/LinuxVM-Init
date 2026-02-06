#!/usr/bin/env bash

manage_center() {
  while true; do
    say '==== 常驻管理中心 ====' '==== Persistent Management Center ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) SSH 管理'
      printf '%s\n' '2) 防火墙管理 (ufw/iptables)'
      printf '%s\n' '3) fail2ban 管理'
      printf '%s\n' '4) Docker 管理'
      printf '%s\n' '5) Swap 管理'
      printf '%s\n' '6) 自动安全更新管理'
      printf '%s\n' '7) 快照与回滚'
      printf '%s\n' '8) 巡检与每日简报'
      printf '%s\n' 'b) 返回主菜单'
    else
      printf '%s\n' '1) SSH management'
      printf '%s\n' '2) Firewall management (ufw/iptables)'
      printf '%s\n' '3) fail2ban management'
      printf '%s\n' '4) Docker management'
      printf '%s\n' '5) Swap management'
      printf '%s\n' '6) Unattended upgrades management'
      printf '%s\n' '7) Snapshot and restore'
      printf '%s\n' '8) Inspection and daily report'
      printf '%s\n' 'b) Back to main menu'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) ssh_manage ;;
      2) firewall_manage ;;
      3) fail2ban_manage ;;
      4) docker_manage ;;
      5) swap_manage ;;
      6) unattended_manage ;;
      7) snapshot_manage ;;
      8) monitor_manage ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
