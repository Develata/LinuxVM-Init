#!/usr/bin/env bash

set_sshd_option() {
  local key="$1"
  local value="$2"
  local file='/etc/ssh/sshd_config'
  if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+" "$file"; then
    sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "$file"
  else
    printf '%s %s\n' "$key" "$value" >>"$file"
  fi
}

restart_ssh() {
  systemctl restart sshd 2>/dev/null || systemctl restart ssh
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
