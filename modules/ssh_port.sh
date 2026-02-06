#!/usr/bin/env bash

choose_ssh_port() {
  local mode
  say '选择端口方式：1 手动输入 / 2 随机生成' 'Choose port mode: 1 manual / 2 random'
  printf '%s ' '> '
  read -r mode
  if [ "$mode" != '1' ] && [ "$mode" != '2' ]; then
    say '输入无效，请输入 1 或 2。' 'Invalid input, please enter 1 or 2.'
    return 1
  fi
  if [ "$mode" = '1' ]; then
    local input_port
    local existing_port
    existing_port="$(current_ssh_port)"
    ask '请输入 SSH 端口(1024-65535)：' 'Enter SSH port (1024-65535):' input_port
    if ! [[ "$input_port" =~ ^[0-9]+$ ]] || [ "$input_port" -lt 1024 ] || [ "$input_port" -gt 65535 ]; then
      say '端口无效，取消操作。' 'Invalid port, aborting.'
      return 1
    fi
    if is_reserved_port "$input_port"; then
      say '该端口属于保留黑名单，请换一个端口。' 'This port is in reserved blacklist. Choose another one.'
      return 1
    fi
    if [ "$input_port" != "$existing_port" ] && is_port_in_use "$input_port"; then
      say '该端口已被占用，请换一个端口。' 'This port is already in use. Choose another one.'
      return 1
    fi
    SSH_PORT="$input_port"
  else
    SSH_PORT="$(pick_random_free_port || true)"
    if [ -z "$SSH_PORT" ]; then
      say '未能找到空闲随机端口，请手动输入。' 'Failed to find a free random port. Please enter one manually.'
      return 1
    fi
  fi

  say "新 SSH 端口：$SSH_PORT" "New SSH port: $SSH_PORT"
  if ! confirm '确认使用该端口？[y/N]' 'Confirm this port? [y/N]'; then
    return 2
  fi
  return 0
}

ssh_configure() {
  say '风险提示：改 SSH 端口且未放行会断开连接。' 'Warning: changing SSH port without firewall allowance can cut off access.'
  say '请保持当前 SSH 会话，不要中断。' 'Keep your current SSH session open.'

  if [ -n "$SSH_PORT" ]; then
    say "当前预设 SSH 端口：$SSH_PORT" "Current preset SSH port: $SSH_PORT"
    if confirm '是否重新选择 SSH 端口？[y/N]' 'Choose a different SSH port? [y/N]'; then
      choose_ssh_port || return $?
    fi
  else
    choose_ssh_port || return $?
  fi

  say '风险提示：禁用 root 登录后，root 将无法 SSH 登录。' 'Warning: disabling root login blocks SSH root access.'
  local disable_root='no'
  if confirm '是否禁用 root 登录？输入 y 继续。' 'Disable root login? Enter y to proceed.'; then
    disable_root='yes'
  fi

  backup_file '/etc/ssh/sshd_config'
  set_sshd_option 'Port' "$SSH_PORT"
  if is_installed ufw; then
    run_cmd "ufw allow $SSH_PORT"
  fi
  if [ "$disable_root" = 'yes' ]; then
    set_sshd_option 'PermitRootLogin' 'no'
  fi

  if [ "$DISTRO_ID" = 'ubuntu24' ]; then
    say '风险提示：Ubuntu24 可能需要配置 ssh.socket 双栈端口。' 'Warning: Ubuntu24 may require ssh.socket dual-stack config.'
    if confirm '是否写入 ssh.socket 端口配置？[y/N]' 'Write ssh.socket port config? [y/N]'; then
      mkdir -p /etc/systemd/system/ssh.socket.d
      cat > /etc/systemd/system/ssh.socket.d/override.conf <<EOF
[Socket]
ListenStream=
ListenStream=0.0.0.0:$SSH_PORT
ListenStream=[::]:$SSH_PORT
ListenStream=0.0.0.0:22
ListenStream=[::]:22
EOF
      run_cmd 'systemctl daemon-reload'
      run_cmd 'systemctl restart ssh.socket'
    fi
  fi

  if ! validate_sshd_config; then
    say 'SSH 配置语法校验失败，已回滚到备份。' 'SSH config validation failed, rolled back to backup.'
    rollback_sshd_config
    return 1
  fi

  if ! restart_ssh; then
    say 'SSH 服务重启失败，已回滚到备份并尝试恢复服务。' 'SSH restart failed, rolled back and trying to recover service.'
    rollback_sshd_config
    restart_ssh || true
    return 1
  fi
  say 'SSH 服务重启成功。' 'SSH service restarted successfully.'
  print_ssh_test_hint
}
