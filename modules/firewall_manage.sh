#!/usr/bin/env bash

ufw_manage_menu() {
  while true; do
    say '==== UFW 管理 ====' '==== UFW Management ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 查看状态'
      printf '%s\n' '2) 放行端口'
      printf '%s\n' '3) 拒绝端口'
      printf '%s\n' '4) 删除规则(按编号)'
      printf '%s\n' '5) 启用防火墙'
      printf '%s\n' '6) 关闭防火墙'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) Show status'
      printf '%s\n' '2) Allow port'
      printf '%s\n' '3) Deny port'
      printf '%s\n' '4) Delete rule by number'
      printf '%s\n' '5) Enable firewall'
      printf '%s\n' '6) Disable firewall'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) run_cmd 'ufw status numbered' ;;
      2)
        ask '输入要放行的端口：' 'Enter port to allow:' port
        if ! is_valid_port "$port"; then
          say '端口无效。' 'Invalid port.'
        else
          run_cmd "ufw allow $port"
        fi
        ;;
      3)
        ask '输入要拒绝的端口：' 'Enter port to deny:' port
        if ! is_valid_port "$port"; then
          say '端口无效。' 'Invalid port.'
        else
          run_cmd "ufw deny $port"
        fi
        ;;
      4)
        run_cmd 'ufw status numbered'
        ask '输入要删除的规则编号：' 'Enter rule number to delete:' rule_no
        if ! [[ "$rule_no" =~ ^[0-9]+$ ]]; then
          say '编号无效。' 'Invalid number.'
        else
          run_cmd "ufw --force delete $rule_no"
        fi
        ;;
      5) run_cmd 'ufw --force enable' ;;
      6) run_cmd 'ufw disable' ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}

iptables_delete_port_rules() {
  local port="$1"
  while iptables_has_rule "$port"; do
    run_cmd "iptables -D INPUT -p tcp --dport $port -j ACCEPT"
  done
}

iptables_manage_menu() {
  while true; do
    say '==== iptables 管理 ====' '==== iptables Management ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 查看规则'
      printf '%s\n' '2) 放行端口'
      printf '%s\n' '3) 删除端口放行'
      printf '%s\n' '4) 保存规则'
      printf '%s\n' '5) 从备份恢复规则'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) Show rules'
      printf '%s\n' '2) Allow port'
      printf '%s\n' '3) Remove allowed port'
      printf '%s\n' '4) Save rules'
      printf '%s\n' '5) Restore from backup'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) run_cmd 'iptables -L -n --line-numbers' ;;
      2)
        ask '输入要放行的端口：' 'Enter port to allow:' port
        if ! is_valid_port "$port"; then
          say '端口无效。' 'Invalid port.'
        else
          iptables_allow_port "$port"
          run_cmd 'netfilter-persistent save'
        fi
        ;;
      3)
        ask '输入要删除放行的端口：' 'Enter port to remove:' port
        if ! is_valid_port "$port"; then
          say '端口无效。' 'Invalid port.'
        else
          iptables_delete_port_rules "$port"
          run_cmd 'netfilter-persistent save'
        fi
        ;;
      4)
        run_cmd 'iptables-save > /etc/iptables/rules.v4'
        run_cmd 'netfilter-persistent save'
        ;;
      5)
        if [ ! -f /etc/iptables/rules.v4.bak ]; then
          say '未找到备份文件 /etc/iptables/rules.v4.bak' 'Backup file /etc/iptables/rules.v4.bak not found'
        else
          run_cmd 'iptables-restore < /etc/iptables/rules.v4.bak'
          run_cmd 'iptables-save > /etc/iptables/rules.v4'
          run_cmd 'netfilter-persistent save'
        fi
        ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}

firewall_manage() {
  local current_mode
  current_mode="$(state_get 'FIREWALL_MODE')"
  if [ -n "$current_mode" ]; then
    say "当前记录模式：$current_mode" "Current recorded mode: $current_mode"
  fi
  say '0) 首次安装/初始化防火墙  1) 管理 ufw  2) 管理 iptables' '0) Initial firewall setup  1) Manage ufw  2) Manage iptables'
  printf '%s ' '> '
  read -r mode
  if [ -z "$mode" ] && [ -n "$current_mode" ]; then
    mode="$([ "$current_mode" = 'iptables' ] && printf '2' || printf '1')"
  fi
  case "$mode" in
    0)
      firewall_setup
      ;;
    1)
      if ! is_installed ufw; then
        say '未检测到 ufw。' 'ufw is not installed.'
        return 1
      fi
      state_set 'FIREWALL_MODE' 'ufw'
      ufw_manage_menu
      ;;
    2)
      if ! is_installed iptables; then
        say '未检测到 iptables。' 'iptables is not installed.'
        return 1
      fi
      state_set 'FIREWALL_MODE' 'iptables'
      iptables_manage_menu
      ;;
    *)
      say '输入无效。' 'Invalid input.'
      return 1
      ;;
  esac
}
