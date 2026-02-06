#!/usr/bin/env bash

manage_center() {
  while true; do
    say '==== 常驻管理中心 ====' '==== Persistent Management Center ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 防火墙管理 (ufw/iptables)'
      printf '%s\n' '2) fail2ban 管理'
      printf '%s\n' '3) Docker 管理'
      printf '%s\n' '4) Swap 管理'
      printf '%s\n' '5) 自动安全更新管理'
      printf '%s\n' 'b) 返回主菜单'
    else
      printf '%s\n' '1) Firewall management (ufw/iptables)'
      printf '%s\n' '2) fail2ban management'
      printf '%s\n' '3) Docker management'
      printf '%s\n' '4) Swap management'
      printf '%s\n' '5) Unattended upgrades management'
      printf '%s\n' 'b) Back to main menu'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) firewall_manage ;;
      2) fail2ban_manage ;;
      3) docker_manage ;;
      4) swap_manage ;;
      5) unattended_manage ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
