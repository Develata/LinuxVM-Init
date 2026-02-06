#!/usr/bin/env bash

ssh_show_summary() {
  local port root_login pwd_auth pubkey_auth
  port="$(current_ssh_port)"
  root_login="$(get_sshd_option 'PermitRootLogin')"
  pwd_auth="$(get_sshd_option 'PasswordAuthentication')"
  pubkey_auth="$(get_sshd_option 'PubkeyAuthentication')"

  [ -z "$root_login" ] && root_login='(default)'
  [ -z "$pwd_auth" ] && pwd_auth='(default)'
  [ -z "$pubkey_auth" ] && pubkey_auth='(default)'

  say '==== SSH 配置摘要 ====' '==== SSH Summary ===='
  printf 'Port: %s\n' "$port"
  printf 'PermitRootLogin: %s\n' "$root_login"
  printf 'PasswordAuthentication: %s\n' "$pwd_auth"
  printf 'PubkeyAuthentication: %s\n' "$pubkey_auth"
  run_cmd 'systemctl status ssh --no-pager -l 2>/dev/null || systemctl status sshd --no-pager -l 2>/dev/null || true'
}

ssh_set_root_login() {
  say '风险提示：禁用 root 登录后，root 无法 SSH 登录。' 'Warning: disabling root login blocks SSH root access.'
  say '1) PermitRootLogin no  2) PermitRootLogin yes' '1) PermitRootLogin no  2) PermitRootLogin yes'
  printf '%s ' '> '
  read -r op
  case "$op" in
    1) value='no' ;;
    2) value='yes' ;;
    *)
      say '输入无效。' 'Invalid input.'
      return 1
      ;;
  esac

  backup_file '/etc/ssh/sshd_config'
  snapshot_create 'before-ssh-root-policy'
  set_sshd_option 'PermitRootLogin' "$value"
  if ! apply_sshd_changes; then
    return 1
  fi
  say 'root 登录策略已更新。' 'Root login policy updated.'
}

ssh_set_password_auth() {
  say '风险提示：关闭密码登录前，请确认密钥登录可用。' 'Warning: ensure key login works before disabling password login.'
  say '1) PasswordAuthentication no  2) PasswordAuthentication yes' '1) PasswordAuthentication no  2) PasswordAuthentication yes'
  printf '%s ' '> '
  read -r op
  case "$op" in
    1) value='no' ;;
    2) value='yes' ;;
    *)
      say '输入无效。' 'Invalid input.'
      return 1
      ;;
  esac

  backup_file '/etc/ssh/sshd_config'
  snapshot_create 'before-ssh-password-policy'
  set_sshd_option 'PasswordAuthentication' "$value"
  if [ "$value" = 'no' ]; then
    set_sshd_option 'PubkeyAuthentication' 'yes'
  fi
  if ! apply_sshd_changes; then
    return 1
  fi
  say '密码登录策略已更新。' 'Password authentication policy updated.'
  print_ssh_test_hint
}

ssh_set_pubkey_auth() {
  say '1) PubkeyAuthentication yes  2) PubkeyAuthentication no' '1) PubkeyAuthentication yes  2) PubkeyAuthentication no'
  printf '%s ' '> '
  read -r op
  case "$op" in
    1) value='yes' ;;
    2) value='no' ;;
    *)
      say '输入无效。' 'Invalid input.'
      return 1
      ;;
  esac

  backup_file '/etc/ssh/sshd_config'
  snapshot_create 'before-ssh-pubkey-policy'
  set_sshd_option 'PubkeyAuthentication' "$value"
  if ! apply_sshd_changes; then
    return 1
  fi
  say '密钥登录策略已更新。' 'Public key authentication policy updated.'
}

ssh_show_failed_logins() {
  say '显示最近 50 条 SSH 相关失败日志。' 'Showing latest 50 SSH-related failure logs.'
  run_cmd "journalctl -u ssh -u sshd --no-pager -n 300 2>/dev/null | grep -Ei 'failed|invalid|authentication failure|error' | tail -n 50"
}

ssh_manage() {
  while true; do
    say '==== SSH 管理中心 ====' '==== SSH Management Center ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 查看 SSH 配置摘要'
      printf '%s\n' '2) 仅修改 SSH 端口'
      printf '%s\n' '3) 修改 root 登录策略'
      printf '%s\n' '4) 修改密码登录策略'
      printf '%s\n' '5) 修改密钥登录策略'
      printf '%s\n' '6) 查看 SSH 失败日志'
      printf '%s\n' '7) 配置密钥登录(写入 authorized_keys)'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) Show SSH summary'
      printf '%s\n' '2) Change SSH port only'
      printf '%s\n' '3) Change root login policy'
      printf '%s\n' '4) Change password auth policy'
      printf '%s\n' '5) Change pubkey auth policy'
      printf '%s\n' '6) Show SSH failure logs'
      printf '%s\n' '7) Configure key login (authorized_keys)'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) ssh_show_summary ;;
      2) ssh_change_port_only ;;
      3) ssh_set_root_login ;;
      4) ssh_set_password_auth ;;
      5) ssh_set_pubkey_auth ;;
      6) ssh_show_failed_logins ;;
      7) ssh_key_login ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
