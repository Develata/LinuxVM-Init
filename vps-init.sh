#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

if [ ! -d "$BASE_DIR/lib" ] || [ ! -d "$BASE_DIR/modules" ]; then
  printf '%s\n' "Invalid base path: $BASE_DIR"
  printf '%s\n' 'Please run from a valid LinuxVM-Init directory.'
  exit 1
fi

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
ensure_log
init_summary
require_root
ensure_state_dirs
load_saved_preferences

if [ "$NON_INTERACTIVE" != '1' ]; then
  if [ "${PREF_LANG_LOADED:-0}" = '1' ]; then
    say "已使用上次语言设置：$LANG_CHOICE" "Using saved language: $LANG_CHOICE"
  else
    select_language
  fi
fi

ensure_global_lvm_command || true
say '请保持当前 SSH 会话，不要中断。' 'Keep your current SSH session open.'

if [ -z "$DISTRO_ID" ]; then
  if [ "$NON_INTERACTIVE" = '1' ]; then
    say '非交互模式下必须指定 --distro（或先交互运行一次保存系统选择）。' 'You must provide --distro in non-interactive mode (or run once interactively to save preference).'
    exit 1
  fi
  select_distro
elif [ "$NON_INTERACTIVE" != '1' ] && [ "${PREF_DISTRO_LOADED:-0}" = '1' ]; then
  say "已使用上次系统设置：$DISTRO_ID" "Using saved distro: $DISTRO_ID"
fi

check_distro_consistency
persist_preferences
if [ "$NON_INTERACTIVE" = '1' ]; then
  run_non_interactive_profile
else
  main_menu
fi

print_summary
print_rollback_hints
