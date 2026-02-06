#!/usr/bin/env bash

user_add() {
  say '风险提示：禁用 root 登录前必须有可用 sudo 用户。' 'Warning: you need a sudo user before disabling root login.'
  say '风险提示：加入 sudo 组后该用户拥有管理权限。' 'Warning: sudo group grants admin privileges.'
  ask '请输入要创建的用户名：' 'Enter a username to create:' new_user
  if [ -z "$new_user" ]; then
    say '用户名不能为空。' 'Username cannot be empty.'
    return 1
  fi
  if ! [[ "$new_user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    say '用户名格式无效：仅允许小写字母、数字、下划线和短横线。' 'Invalid username: use lowercase letters, numbers, underscore, hyphen.'
    return 1
  fi
  if id -u "$new_user" >/dev/null 2>&1; then
    say '用户已存在，跳过创建。' 'User already exists, skipping.'
  else
    run_cmd "adduser -- \"$new_user\""
  fi
  if confirm '是否加入 sudo 组？[y/N]' 'Add user to sudo group? [y/N]'; then
    run_cmd "adduser -- \"$new_user\" sudo"
  fi
}
