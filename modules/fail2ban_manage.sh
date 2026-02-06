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

  local source_ip
  source_ip="$(detect_source_ip)"
  if [ -n "$source_ip" ] && ! grep -q "$source_ip" /etc/fail2ban/jail.local; then
    sed -i -E "s|^[[:space:]]*ignoreip[[:space:]]*=.*|& ${source_ip}|" /etc/fail2ban/jail.local
  fi

  snapshot_create 'before-fail2ban-policy-change'
  run_cmd 'systemctl restart fail2ban'
  run_cmd 'fail2ban-client status sshd'
}

fail2ban_ban_ip() {
  local source_ip
  source_ip="$(detect_source_ip)"
  ask '输入要封禁的 IP：' 'Enter IP to ban:' target_ip
  if [ -z "$target_ip" ]; then
    say 'IP 不能为空。' 'IP cannot be empty.'
    return 1
  fi
  if ! is_valid_ip "$target_ip"; then
    say 'IP 格式无效，请输入合法 IPv4/IPv6。' 'Invalid IP format, please use valid IPv4/IPv6.'
    return 1
  fi
  if [ -n "$source_ip" ] && [ "$target_ip" = "$source_ip" ]; then
    say '禁止封禁当前来源 IP，已拦截此操作。' 'Refusing to ban current source IP.'
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
  if ! is_valid_ip "$target_ip"; then
    say 'IP 格式无效，请输入合法 IPv4/IPv6。' 'Invalid IP format, please use valid IPv4/IPv6.'
    return 1
  fi
  run_cmd "fail2ban-client set sshd unbanip $target_ip"
}

fail2ban_manage() {
  while true; do
    say '==== fail2ban 管理 ====' '==== fail2ban Management ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '0) 安装/初始化 fail2ban'
      printf '%s\n' '1) 查看 sshd 状态'
      printf '%s\n' '2) 修改封禁策略'
      printf '%s\n' '3) 手动封禁 IP'
      printf '%s\n' '4) 手动解封 IP'
      printf '%s\n' '5) 查看 fail2ban 运行状态'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '0) Install/init fail2ban'
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
      0) fail2ban_setup ;;
      1)
        if ! is_installed fail2ban-client; then
          say '未安装 fail2ban，请先执行 0) 安装/初始化。' 'fail2ban not installed. Run 0) install/init first.'
        else
          run_cmd 'fail2ban-client status sshd'
        fi
        ;;
      2)
        if ! is_installed fail2ban-client; then
          say '未安装 fail2ban，请先执行 0) 安装/初始化。' 'fail2ban not installed. Run 0) install/init first.'
        else
          fail2ban_update_policy
        fi
        ;;
      3)
        if ! is_installed fail2ban-client; then
          say '未安装 fail2ban，请先执行 0) 安装/初始化。' 'fail2ban not installed. Run 0) install/init first.'
        else
          fail2ban_ban_ip
        fi
        ;;
      4)
        if ! is_installed fail2ban-client; then
          say '未安装 fail2ban，请先执行 0) 安装/初始化。' 'fail2ban not installed. Run 0) install/init first.'
        else
          fail2ban_unban_ip
        fi
        ;;
      5)
        if ! is_installed fail2ban-client; then
          say '未安装 fail2ban，请先执行 0) 安装/初始化。' 'fail2ban not installed. Run 0) install/init first.'
        else
          run_cmd 'systemctl status fail2ban --no-pager -l'
        fi
        ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
