#!/usr/bin/env bash

set_sshd_option() {
  local key="$1"
  local value="$2"
  local file='/etc/ssh/sshd_config'
  if grep -qEi "^[[:space:]]*${key}[[:space:]]+" "$file"; then
    # Replace only the first uncommented line (case-insensitive key match)
    sed -i -E "0,/^[[:space:]]*${key}[[:space:]]+/I s|^[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|I" "$file"
  elif grep -qEi "^[[:space:]]*#[[:space:]]*${key}[[:space:]]+" "$file"; then
    # Uncomment and set only the first commented line
    sed -i -E "0,/^[[:space:]]*#[[:space:]]*${key}[[:space:]]+/I s|^[[:space:]]*#[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|I" "$file"
  else
    printf '%s %s\n' "$key" "$value" >>"$file"
  fi
}

restart_ssh() {
  systemctl restart sshd 2>/dev/null || systemctl restart ssh
}

user_in_admin_group() {
  local user="$1"
  id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -Eq '^(sudo|wheel)$'
}

user_has_ssh_key() {
  local user="$1"
  local user_home
  user_home="$(getent passwd "$user" | awk -F: '{print $6}')"
  [ -n "$user_home" ] && [ -s "$user_home/.ssh/authorized_keys" ]
}

sudo_user_exists() {
  local user
  while IFS=: read -r user _; do
    [ -n "$user" ] || continue
    if user_in_admin_group "$user"; then
      return 0
    fi
  done < /etc/passwd
  return 1
}

admin_key_login_exists() {
  local future_root_login="${1:-}"
  local current_root_login user
  current_root_login="$(get_sshd_option 'PermitRootLogin')"
  [ -n "$future_root_login" ] || future_root_login="$current_root_login"

  if [ "$future_root_login" != 'no' ] && user_has_ssh_key root; then
    return 0
  fi

  while IFS=: read -r user _; do
    [ -n "$user" ] || continue
    if user_in_admin_group "$user" && user_has_ssh_key "$user"; then
      return 0
    fi
  done < /etc/passwd
  return 1
}

ensure_root_disable_safe() {
  local current_password_auth
  current_password_auth="$(get_sshd_option 'PasswordAuthentication')"
  if ! sudo_user_exists; then
    say '未检测到 sudo/wheel 管理用户，拒绝禁用 root 登录。' 'No sudo/wheel admin user detected; refusing to disable root login.'
    return 1
  fi
  if [ "$current_password_auth" = 'no' ] && ! admin_key_login_exists 'no'; then
    say '密码登录已关闭，且未检测到带 SSH key 的 sudo/wheel 用户，拒绝禁用 root 登录。' 'Password login is disabled and no sudo/wheel user with SSH key was detected; refusing to disable root login.'
    return 1
  fi
}

ensure_password_disable_safe() {
  local future_root_login="${1:-}"
  if ! admin_key_login_exists "$future_root_login"; then
    say '未检测到可用的 root 或 sudo/wheel 用户 SSH key，拒绝关闭密码登录。' 'No usable root or sudo/wheel user SSH key detected; refusing to disable password login.'
    return 1
  fi
}

backup_ssh_socket_override() {
  local file='/etc/systemd/system/ssh.socket.d/override.conf'
  local marker='/etc/systemd/system/ssh.socket.d/.linuxvm-init-override-was-absent'
  mkdir -p /etc/systemd/system/ssh.socket.d
  if [ -f "$file" ]; then
    backup_file "$file"
    rm -f "$marker"
  else
    touch "$marker"
  fi
}

rollback_ssh_socket_override() {
  local file='/etc/systemd/system/ssh.socket.d/override.conf'
  local marker='/etc/systemd/system/ssh.socket.d/.linuxvm-init-override-was-absent'
  if [ -f "${file}.bak" ]; then
    mkdir -p /etc/systemd/system/ssh.socket.d
    cp "${file}.bak" "$file"
  elif [ -f "$marker" ]; then
    rm -f "$file"
  fi
  rm -f "$marker"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart ssh.socket >/dev/null 2>&1 || true
}

clear_ssh_socket_override_marker() {
  rm -f /etc/systemd/system/ssh.socket.d/.linuxvm-init-override-was-absent
}

get_sshd_option() {
  local key="$1"
  local file='/etc/ssh/sshd_config'
  awk -v k="$key" 'BEGIN{IGNORECASE=1} $1==k {print $2; found=1; exit} END{if(!found) print ""}' "$file" 2>/dev/null
}

validate_sshd_config() {
  local sshd_bin
  sshd_bin="$(command -v sshd 2>/dev/null || true)"
  if [ -z "$sshd_bin" ]; then
    return 1
  fi
  "$sshd_bin" -t -f /etc/ssh/sshd_config >/dev/null 2>&1
}

rollback_sshd_config() {
  if [ -f /etc/ssh/sshd_config.bak ]; then
    cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
  fi
}

apply_sshd_changes() {
  if ! validate_sshd_config; then
    say 'SSH 配置语法校验失败，已回滚到备份。' 'SSH config validation failed, rolled back to backup.'
    rollback_sshd_config
    rollback_ssh_socket_override
    return 1
  fi

  if ! restart_ssh; then
    say 'SSH 服务重启失败，已回滚到备份并尝试恢复服务。' 'SSH restart failed, rolled back and trying to recover service.'
    rollback_sshd_config
    rollback_ssh_socket_override
    restart_ssh || true
    return 1
  fi

  if is_installed ss || is_installed netstat; then
    local port
    port="$(effective_ssh_port)"
    if ! is_port_in_use "$port"; then
      say "SSH 新端口未检测到监听，已回滚：$port" "SSH new port is not listening, rolled back: $port"
      rollback_sshd_config
      rollback_ssh_socket_override
      restart_ssh || true
      return 1
    fi
  fi
  clear_ssh_socket_override_marker
  return 0
}

print_ssh_test_hint() {
  local port
  port="$(effective_ssh_port)"
  say '请先在新终端测试连接成功，再关闭当前会话。' 'Test SSH in a new terminal before closing current session.'
  if [ "$LANG_CHOICE" = 'zh' ]; then
    printf '%s\n' "测试命令(替换用户名和IP): ssh -p ${port} YOUR_USER@YOUR_SERVER_IP"
  else
    printf '%s\n' "Test command (replace user and IP): ssh -p ${port} YOUR_USER@YOUR_SERVER_IP"
  fi
}

current_ssh_port() {
  local p
  p="$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2; exit}' /etc/ssh/sshd_config 2>/dev/null)"
  if [ -n "$p" ]; then
    printf '%s\n' "$p"
  else
    printf '%s\n' '22'
  fi
}

effective_ssh_port() {
  if [ -n "$SSH_PORT" ]; then
    printf '%s\n' "$SSH_PORT"
  else
    current_ssh_port
  fi
}

rand_port() {
  if is_installed shuf; then
    shuf -i 20000-60999 -n 1
  else
    printf '%s\n' "$((20000 + RANDOM % 41000))"
  fi
}

is_reserved_port() {
  local port="$1"
  case "$port" in
    20|21|22|23|25|53|67|68|69|80|110|123|135|137|138|139|143|161|162|389|443|445|465|514|587|631|873|993|995|1080|1433|1521|2049|2375|2376|3306|3389|3690|5432|5672|5900|5984|6379|6443|6667|7001|8080|8081|8443|9000|9092|9200|9300|11211|27017|25565)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_port_in_use() {
  local port="$1"
  if is_installed ss; then
    ss -ltnH 2>/dev/null | awk -v p="$port" '$4 ~ ":" p "$" {found=1} END {exit found ? 0 : 1}'
    return $?
  fi
  if is_installed netstat; then
    netstat -lnt 2>/dev/null | awk -v p="$port" '$4 ~ ":" p "$" {found=1} END {exit found ? 0 : 1}'
    return $?
  fi
  return 1
}

pick_random_free_port() {
  local tries=0
  local candidate
  while [ "$tries" -lt 30 ]; do
    candidate="$(rand_port)"
    if is_reserved_port "$candidate"; then
      tries=$((tries + 1))
      continue
    fi
    if ! is_port_in_use "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    tries=$((tries + 1))
  done
  return 1
}
