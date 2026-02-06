#!/usr/bin/env bash

ssh_key_login() {
  say '风险提示：启用密钥登录将强制关闭密码登录。' 'Warning: enabling key login will disable password login.'
  local target_user
  if [ -n "${SUDO_USER:-}" ]; then
    target_user="$SUDO_USER"
  else
    ask '请输入要配置密钥的用户名：' 'Enter username for key login:' target_user
  fi
  if [ -z "$target_user" ]; then
    say '用户名不能为空。' 'Username cannot be empty.'
    return 1
  fi
  if ! id -u "$target_user" >/dev/null 2>&1; then
    say '用户不存在。' 'User does not exist.'
    return 1
  fi

  local user_home
  user_home="$(getent passwd "$target_user" | awk -F: '{print $6}')"
  if [ -z "$user_home" ]; then
    say '无法获取用户主目录。' 'Failed to get user home directory.'
    return 1
  fi

  local pubkey
  ask '请粘贴公钥内容：' 'Paste the public key:' pubkey
  if [ -z "$pubkey" ]; then
    say '公钥不能为空。' 'Public key cannot be empty.'
    return 1
  fi

  mkdir -p "$user_home/.ssh"
  printf '%s\n' "$pubkey" >>"$user_home/.ssh/authorized_keys"
  chown -R "$target_user:$target_user" "$user_home/.ssh"
  chmod 700 "$user_home/.ssh"
  chmod 600 "$user_home/.ssh/authorized_keys"

  backup_file '/etc/ssh/sshd_config'
  set_sshd_option 'PasswordAuthentication' 'no'
  set_sshd_option 'PubkeyAuthentication' 'yes'
  restart_ssh
  say '已启用密钥登录并禁用密码登录。' 'Key login enabled and password login disabled.'
}
