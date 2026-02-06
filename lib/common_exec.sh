#!/usr/bin/env bash

ensure_log() {
  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE" 2>/dev/null || true
  fi
}

log_line() {
  printf '%s\n' "$1" >>"$LOG_FILE" 2>/dev/null || true
}

run_cmd() {
  local cmd="$1"
  printf '>> %s\n' "$cmd"
  log_line ">> $cmd"
  bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"
  return "${PIPESTATUS[0]}"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    say '请以 root 身份运行。' 'Please run as root.'
    exit 1
  fi
}

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "${file}.bak"
  fi
}

is_installed() {
  command -v "$1" >/dev/null 2>&1
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

is_valid_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local o1 o2 o3 o4
  IFS='.' read -r o1 o2 o3 o4 <<EOF
$ip
EOF
  for o in "$o1" "$o2" "$o3" "$o4"; do
    [ "$o" -ge 0 ] && [ "$o" -le 255 ] || return 1
  done
  return 0
}

is_valid_ipv6() {
  local ip="$1"
  [[ "$ip" =~ : ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - <<'PY' "$ip"
import ipaddress, sys
try:
    ipaddress.IPv6Address(sys.argv[1])
except Exception:
    sys.exit(1)
sys.exit(0)
PY
}

is_valid_ip() {
  local ip="$1"
  is_valid_ipv4 "$ip" || is_valid_ipv6 "$ip"
}

detect_source_ip() {
  local candidate=''
  if [ -n "${SSH_CONNECTION:-}" ]; then
    candidate="$(printf '%s' "$SSH_CONNECTION" | awk '{print $1}')"
  elif [ -n "${SSH_CLIENT:-}" ]; then
    candidate="$(printf '%s' "$SSH_CLIENT" | awk '{print $1}')"
  fi
  if is_valid_ip "$candidate"; then
    printf '%s\n' "$candidate"
  else
    printf '%s\n' ''
  fi
}
