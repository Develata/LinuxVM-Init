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
  printf '%b>> %s%b\n' "${C_BOLD}${C_BLUE}" "$cmd" "$C_RESET"
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

ensure_global_lvm_command() {
  local target_cmd source_script current_target
  target_cmd='/usr/local/bin/lvm'
  source_script="$BASE_DIR/vps-init.sh"

  if [ ! -f "$source_script" ]; then
    return 1
  fi

  if [ ! -e "$target_cmd" ]; then
    chmod +x "$source_script" 2>/dev/null || true
    ln -sf "$source_script" "$target_cmd"
    say '已自动安装全局命令：lvm' 'Global command installed automatically: lvm'
    return 0
  fi

  if [ -L "$target_cmd" ]; then
    current_target="$(readlink -f "$target_cmd" 2>/dev/null || true)"
    if [ "$current_target" = "$source_script" ]; then
      return 0
    fi
    say "检测到已存在 lvm 命令链接到：$current_target" "Detected existing lvm symlink to: $current_target"
    say '请手动处理后再重试（避免覆盖你现有命令）。' 'Please resolve it manually to avoid overriding existing command.'
    return 1
  fi

  say '检测到系统已有非软链接的 lvm 命令。' 'Detected existing non-symlink lvm command.'
  say '请手动处理后再重试（避免误删系统命令）。' 'Please resolve it manually to avoid deleting system command.'
  return 1
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
