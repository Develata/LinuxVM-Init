#!/usr/bin/env bash

fail2ban_set_value() {
  local key="$1"
  local value="$2"
  local file='/etc/fail2ban/jail.local'
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
  else
    printf '%s = %s\n' "$key" "$value" >>"$file"
  fi
}

fail2ban_update_policy() {
  if [ ! -f /etc/fail2ban/jail.local ]; then
    say '/etc/fail2ban/jail.local 不存在，请先执行 fail2ban 配置。' '/etc/fail2ban/jail.local not found, run fail2ban setup first.'
    return 1
  fi

  ask '新的 maxretry (回车保持不变):' 'New maxretry (Enter to keep):' in_maxretry
  ask '新的 findtime 秒数 (回车保持不变):' 'New findtime seconds (Enter to keep):' in_findtime
  ask '新的 bantime 秒数 (可填 -1 永久，回车保持不变):' 'New bantime seconds (-1 permanent, Enter to keep):' in_bantime

  if [ -n "$in_maxretry" ]; then
    if [[ "$in_maxretry" =~ ^[0-9]+$ ]] && [ "$in_maxretry" -gt 0 ]; then
      fail2ban_set_value 'maxretry' "$in_maxretry"
    else
      say 'maxretry 输入无效，已忽略。' 'Invalid maxretry, ignored.'
    fi
  fi
  if [ -n "$in_findtime" ]; then
    if [[ "$in_findtime" =~ ^[0-9]+$ ]] && [ "$in_findtime" -gt 0 ]; then
      fail2ban_set_value 'findtime' "$in_findtime"
    else
      say 'findtime 输入无效，已忽略。' 'Invalid findtime, ignored.'
    fi
  fi
  if [ -n "$in_bantime" ]; then
    if [[ "$in_bantime" =~ ^-?[0-9]+$ ]]; then
      fail2ban_set_value 'bantime' "$in_bantime"
    else
      say 'bantime 输入无效，已忽略。' 'Invalid bantime, ignored.'
    fi
  fi

  run_cmd 'systemctl restart fail2ban'
  run_cmd 'fail2ban-client status sshd'
}

fail2ban_ban_ip() {
  ask '输入要封禁的 IP：' 'Enter IP to ban:' target_ip
  if [ -z "$target_ip" ]; then
    say 'IP 不能为空。' 'IP cannot be empty.'
    return 1
  fi
  run_cmd "fail2ban-client set sshd banip $target_ip"
}

fail2ban_unban_ip() {
  ask '输入要解封的 IP：' 'Enter IP to unban:' target_ip
  if [ -z "$target_ip" ]; then
    say 'IP 不能为空。' 'IP cannot be empty.'
    return 1
  fi
  run_cmd "fail2ban-client set sshd unbanip $target_ip"
}

fail2ban_manage() {
  if ! is_installed fail2ban-client; then
    say '未安装 fail2ban，请先执行 fail2ban 配置。' 'fail2ban is not installed, run setup first.'
    return 1
  fi

  while true; do
    say '==== fail2ban 管理 ====' '==== fail2ban Management ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 查看 sshd 状态'
      printf '%s\n' '2) 修改封禁策略'
      printf '%s\n' '3) 手动封禁 IP'
      printf '%s\n' '4) 手动解封 IP'
      printf '%s\n' '5) 查看 fail2ban 运行状态'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) Show sshd jail status'
      printf '%s\n' '2) Update ban policy'
      printf '%s\n' '3) Ban IP manually'
      printf '%s\n' '4) Unban IP manually'
      printf '%s\n' '5) Show fail2ban service status'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) run_cmd 'fail2ban-client status sshd' ;;
      2) fail2ban_update_policy ;;
      3) fail2ban_ban_ip ;;
      4) fail2ban_unban_ip ;;
      5) run_cmd 'systemctl status fail2ban --no-pager -l' ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
