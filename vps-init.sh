#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

source "$BASE_DIR/lib/common.sh"
source "$BASE_DIR/modules/system.sh"
source "$BASE_DIR/modules/tools.sh"
source "$BASE_DIR/modules/users.sh"
source "$BASE_DIR/modules/ssh_common.sh"
source "$BASE_DIR/modules/ssh_port.sh"
source "$BASE_DIR/modules/ssh_auth.sh"
source "$BASE_DIR/modules/ssh_manage.sh"
source "$BASE_DIR/modules/snapshot.sh"
source "$BASE_DIR/modules/ufw.sh"
source "$BASE_DIR/modules/firewall_manage.sh"
source "$BASE_DIR/modules/swap.sh"
source "$BASE_DIR/modules/docker.sh"
source "$BASE_DIR/modules/logrotate.sh"
source "$BASE_DIR/modules/fail2ban.sh"
source "$BASE_DIR/modules/fail2ban_manage.sh"
source "$BASE_DIR/modules/unattended.sh"
source "$BASE_DIR/modules/1panel.sh"
source "$BASE_DIR/modules/monitor.sh"
source "$BASE_DIR/modules/safe_mode.sh"
source "$BASE_DIR/modules/update.sh"
source "$BASE_DIR/modules/panel_main.sh"

run_step() {
  local step_name="$1"
  local fn_name="$2"
  "$fn_name"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    record_step "$step_name" 'success'
  elif [ "$rc" -eq 2 ]; then
    record_step "$step_name" 'skipped'
  else
    record_step "$step_name" 'failed'
  fi
  return "$rc"
}

parse_args "$@"
if [ "$NON_INTERACTIVE" != '1' ]; then
  select_language
fi

ensure_log
init_summary
require_root
ensure_state_dirs
ensure_global_lvm_command || true
say '请保持当前 SSH 会话，不要中断。' 'Keep your current SSH session open.'

if [ -z "$DISTRO_ID" ]; then
  if [ "$NON_INTERACTIVE" = '1' ]; then
    say '非交互模式下必须指定 --distro。' 'You must provide --distro in non-interactive mode.'
    exit 1
  fi
  select_distro
fi

check_distro_consistency
if [ "$NON_INTERACTIVE" = '1' ]; then
  run_non_interactive_profile
else
  main_menu
fi

print_summary
print_rollback_hints
