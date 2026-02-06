#!/usr/bin/env bash
set -u
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
source "$BASE_DIR/modules/manage_center.sh"
source "$BASE_DIR/modules/monitor.sh"
parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --non-interactive) NON_INTERACTIVE='1' ;;
      --yes) NI_AUTO_YES='1' ;;
      --lang)
        shift
        [ "${1:-}" = 'en' ] && LANG_CHOICE='en' || LANG_CHOICE='zh'
        ;;
      --distro)
        shift
        DISTRO_ID="${1:-}"
        ;;
    esac
    shift
  done
}
validate_distro_id() {
  case "$DISTRO_ID" in
    debian10|debian11|debian12|debian13|ubuntu22|ubuntu24) return 0 ;;
    *) return 1 ;;
  esac
}
run_non_interactive_profile() {
  if [ -z "${NI_AUTO_YES:-}" ] || [ "${NI_AUTO_YES}" = '0' ]; then
    NI_AUTO_YES='1'
  fi
  if ! validate_distro_id; then
    say '非交互模式必须通过 --distro 指定受支持系统。' 'Non-interactive mode requires --distro with supported value.'
    return 1
  fi
  NI_RUN_SYSTEM_UPDATE="${NI_RUN_SYSTEM_UPDATE:-1}"
  NI_RUN_TOOLS="${NI_RUN_TOOLS:-1}"
  NI_RUN_FIREWALL="${NI_RUN_FIREWALL:-0}"
  NI_RUN_FAIL2BAN="${NI_RUN_FAIL2BAN:-0}"
  NI_RUN_UNATTENDED="${NI_RUN_UNATTENDED:-1}"

  [ "$NI_RUN_SYSTEM_UPDATE" = '1' ] && run_step 'system_update' system_update
  [ "$NI_RUN_TOOLS" = '1' ] && run_step 'tools_install' tools_install
  [ "$NI_RUN_FIREWALL" = '1' ] && run_step 'firewall_setup' firewall_setup
  [ "$NI_RUN_FAIL2BAN" = '1' ] && run_step 'fail2ban_setup' fail2ban_setup
  [ "$NI_RUN_UNATTENDED" = '1' ] && run_step 'unattended_enable' unattended_enable
}

select_language() {
  printf '%s\n' 'Select language / 选择语言'
  printf '%s\n' '1) 中文'
  printf '%s\n' '2) English'
  printf '%s ' '> '
  read -r choice
  case "$choice" in
    2) LANG_CHOICE='en' ;;
    *) LANG_CHOICE='zh' ;;
  esac
}

select_distro() {
  say '请选择当前系统版本（必须手动选择）' 'Please choose your system (manual selection required).'
  printf '%s\n' '1) debian10'
  printf '%s\n' '2) debian11'
  printf '%s\n' '3) debian12'
  printf '%s\n' '4) debian13'
  printf '%s\n' '5) ubuntu22'
  printf '%s\n' '6) ubuntu24'
  printf '%s ' '> '
  read -r choice
  case "$choice" in
    1) DISTRO_ID='debian10' ;;
    2) DISTRO_ID='debian11' ;;
    3) DISTRO_ID='debian12' ;;
    4) DISTRO_ID='debian13' ;;
    5) DISTRO_ID='ubuntu22' ;;
    6) DISTRO_ID='ubuntu24' ;;
    *) DISTRO_ID='' ;;
  esac
  if [ -z "$DISTRO_ID" ]; then
    say '选择无效，请重新选择。' 'Invalid choice. Please select again.'
    select_distro
  fi
}

check_distro_consistency() {
  local actual=''
  if [ -r /etc/os-release ]; then
    local os_id os_ver major
    os_id="$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release)"
    os_ver="$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release)"
    major="${os_ver%%.*}"
    case "$os_id" in
      debian) actual="debian${major}" ;;
      ubuntu) actual="ubuntu${major}" ;;
    esac
  fi
  if [ -n "$actual" ] && [ "$actual" != "$DISTRO_ID" ]; then
    say "风险提示：你选择的是 $DISTRO_ID，但系统检测为 $actual，后续可能失败。" "Warning: you selected $DISTRO_ID but detected system is $actual. Steps may fail."
  fi
}

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

recommended_flow() {
  say '推荐一键组合将执行多个步骤。' 'Recommended bundle will run multiple steps.'
  say '风险提示：请保持当前 SSH 会话，不要中断。' 'Warning: keep your current SSH session open.'
  if ! confirm '继续执行？[y/N]' 'Proceed? [y/N]'; then
    return 2
  fi
  run_step 'system_update' system_update
  run_step 'tools_install' tools_install
  run_step 'user_add' user_add
  if confirm '是否执行 SSH 安全设置（默认跳过）？[y/N]' 'Apply SSH hardening (default skip)? [y/N]'; then
    choose_ssh_port
    local p_rc=$?
    if [ "$p_rc" -eq 0 ]; then
      record_step 'choose_ssh_port' 'success'
    elif [ "$p_rc" -eq 2 ]; then
      record_step 'choose_ssh_port' 'skipped'
    else
      record_step 'choose_ssh_port' 'failed'
    fi
    run_step 'firewall_setup' firewall_setup
    run_step 'ssh_configure' ssh_configure
  else
    record_step 'choose_ssh_port' 'skipped'
    run_step 'firewall_setup' firewall_setup
    record_step 'ssh_configure' 'skipped'
  fi
  run_step 'unattended_enable' unattended_enable
}

main_menu() {
  while true; do
    say '==== LinuxVM-Init 菜单 ====' '==== LinuxVM-Init Menu ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '0) 推荐一键组合'
      printf '%s\n' '1) 系统更新'
      printf '%s\n' '2) 常用工具安装'
      printf '%s\n' '3) 添加普通用户 + sudo'
      printf '%s\n' '4) 防火墙配置 (ufw/iptables)'
      printf '%s\n' '5) SSH 安全配置（改端口/禁 root）'
      printf '%s\n' '6) SSH 密钥登录配置'
      printf '%s\n' '7) Docker 安装与日志限制'
      printf '%s\n' '8) Swap 配置'
      printf '%s\n' '9) logrotate 配置'
      printf '%s\n' '10) fail2ban 配置'
      printf '%s\n' '11) 安全更新 (unattended-upgrades)'
      printf '%s\n' '12) 1panel 安装'
      printf '%s\n' '13) 常驻管理中心'
      printf '%s\n' 'q) 退出'
    else
      printf '%s\n' '0) Recommended bundle'
      printf '%s\n' '1) System update'
      printf '%s\n' '2) Install tools'
      printf '%s\n' '3) Add user + sudo'
      printf '%s\n' '4) Configure firewall (ufw/iptables)'
      printf '%s\n' '5) SSH hardening (port/root)'
      printf '%s\n' '6) SSH key login'
      printf '%s\n' '7) Install Docker + log limits'
      printf '%s\n' '8) Swap setup'
      printf '%s\n' '9) logrotate setup'
      printf '%s\n' '10) fail2ban setup'
      printf '%s\n' '11) Enable unattended-upgrades'
      printf '%s\n' '12) Install 1panel'
      printf '%s\n' '13) Persistent management center'
      printf '%s\n' 'q) Quit'
    fi
    printf '%s ' '> '
    read -r choice
    case "$choice" in
      0) run_step 'recommended_flow' recommended_flow ;;
      1) run_step 'system_update' system_update ;;
      2) run_step 'tools_install' tools_install ;;
      3) run_step 'user_add' user_add ;;
      4) run_step 'firewall_setup' firewall_setup ;;
      5) run_step 'ssh_configure' ssh_configure ;;
      6) run_step 'ssh_key_login' ssh_key_login ;;
      7) run_step 'docker_install' docker_install ;;
      8) run_step 'swap_setup' swap_setup ;;
      9) run_step 'logrotate_setup' logrotate_setup ;;
      10) run_step 'fail2ban_setup' fail2ban_setup ;;
      11) run_step 'unattended_enable' unattended_enable ;;
      12) run_step 'onepanel_install' onepanel_install ;;
      13) run_step 'manage_center' manage_center ;;
      q|Q) break ;;
      *) say '选择无效。' 'Invalid choice.' ;;
    esac
    pause
  done
}

parse_args "$@"
if [ "$NON_INTERACTIVE" != '1' ]; then
  select_language
fi
ensure_log
init_summary
require_root
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
