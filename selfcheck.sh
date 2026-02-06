#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass_count=0
warn_count=0
fail_count=0

ok() {
  pass_count=$((pass_count + 1))
  printf '[OK] %s\n' "$1"
}

warn() {
  warn_count=$((warn_count + 1))
  printf '[WARN] %s\n' "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf '[FAIL] %s\n' "$1"
}

check_file_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    ok "file exists: ${file#$BASE_DIR/}"
  else
    fail "missing file: ${file#$BASE_DIR/}"
  fi
}

printf 'LinuxVM-Init selfcheck\n'
printf 'Root path: %s\n\n' "$BASE_DIR"

check_file_exists "$BASE_DIR/vps-init.sh"
check_file_exists "$BASE_DIR/lib/common.sh"
check_file_exists "$BASE_DIR/modules/panel_main.sh"
check_file_exists "$BASE_DIR/modules/safe_mode.sh"
check_file_exists "$BASE_DIR/modules/snapshot.sh"
check_file_exists "$BASE_DIR/modules/monitor.sh"

if bash -n "$BASE_DIR/vps-init.sh" "$BASE_DIR/lib/common.sh" "$BASE_DIR"/modules/*.sh "$BASE_DIR/selfcheck.sh"; then
  ok 'shell syntax check passed'
else
  fail 'shell syntax check failed'
fi

if source "$BASE_DIR/lib/common.sh" \
  && source "$BASE_DIR/modules/system.sh" \
  && source "$BASE_DIR/modules/tools.sh" \
  && source "$BASE_DIR/modules/users.sh" \
  && source "$BASE_DIR/modules/ssh_common.sh" \
  && source "$BASE_DIR/modules/ssh_port.sh" \
  && source "$BASE_DIR/modules/ssh_auth.sh" \
  && source "$BASE_DIR/modules/ssh_manage.sh" \
  && source "$BASE_DIR/modules/snapshot.sh" \
  && source "$BASE_DIR/modules/ufw.sh" \
  && source "$BASE_DIR/modules/firewall_manage.sh" \
  && source "$BASE_DIR/modules/swap.sh" \
  && source "$BASE_DIR/modules/docker.sh" \
  && source "$BASE_DIR/modules/logrotate.sh" \
  && source "$BASE_DIR/modules/fail2ban.sh" \
  && source "$BASE_DIR/modules/fail2ban_manage.sh" \
  && source "$BASE_DIR/modules/unattended.sh" \
  && source "$BASE_DIR/modules/1panel.sh" \
  && source "$BASE_DIR/modules/monitor.sh" \
  && source "$BASE_DIR/modules/safe_mode.sh" \
  && source "$BASE_DIR/modules/update.sh" \
  && source "$BASE_DIR/modules/panel_main.sh"; then
  ok 'all modules source successfully'
else
  fail 'failed to source one or more modules'
fi

required_functions='main_menu init_flow ssh_manage docker_manage firewall_manage fail2ban_manage novice_safe_repair snapshot_create monitor_manage script_update'
for fn in $required_functions; do
  if declare -F "$fn" >/dev/null 2>&1; then
    ok "function available: $fn"
  else
    fail "missing function: $fn"
  fi
done

for cmd in bash awk sed systemctl; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "command available: $cmd"
  else
    warn "command missing: $cmd"
  fi
done

printf '\nSummary: %d passed, %d warnings, %d failed\n' "$pass_count" "$warn_count" "$fail_count"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

exit 0
