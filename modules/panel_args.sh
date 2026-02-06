#!/usr/bin/env bash

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
  [ "${NI_AUTO_YES:-0}" = '1' ] || NI_AUTO_YES='1'
  validate_distro_id || {
    say '非交互模式必须通过 --distro 指定受支持系统。' 'Non-interactive mode requires --distro with supported value.'
    return 1
  }

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
  [ -n "$DISTRO_ID" ] || { say '选择无效，请重新选择。' 'Invalid choice. Please select again.'; select_distro; }
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
  [ -n "$actual" ] && [ "$actual" != "$DISTRO_ID" ] &&
    say "风险提示：你选择的是 $DISTRO_ID，但系统检测为 $actual，后续可能失败。" "Warning: you selected $DISTRO_ID but detected system is $actual. Steps may fail."
}
