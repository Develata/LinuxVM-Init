#!/usr/bin/env bash

parse_args() {
  PARSE_LANG_SET='0'
  PARSE_DISTRO_SET='0'
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --non-interactive) NON_INTERACTIVE='1' ;;
      --yes) NI_AUTO_YES='1' ;;
      --lang)
        if [ "$#" -lt 2 ]; then
          printf '%s\n' 'Missing value for --lang (expected: zh or en)' >&2
          return 1
        fi
        shift
        [ "${1:-}" = 'en' ] && LANG_CHOICE='en' || LANG_CHOICE='zh'
        PARSE_LANG_SET='1'
        ;;
      --distro)
        if [ "$#" -lt 2 ]; then
          printf '%s\n' 'Missing value for --distro (expected e.g. debian12, ubuntu24)' >&2
          return 1
        fi
        shift
        DISTRO_ID="${1:-}"
        PARSE_DISTRO_SET='1'
        ;;
    esac
    shift
  done
  : "${NON_INTERACTIVE}"
}

load_saved_preferences() {
  PREF_LANG_LOADED='0'
  PREF_DISTRO_LOADED='0'

  if [ "${PARSE_LANG_SET:-0}" != '1' ]; then
    local saved_lang
    saved_lang="$(state_get 'PREF_LANG')"
    case "$saved_lang" in
      zh|en)
        LANG_CHOICE="$saved_lang"
        PREF_LANG_LOADED='1'
        ;;
    esac
  fi

  if [ "${PARSE_DISTRO_SET:-0}" != '1' ]; then
    local saved_distro
    saved_distro="$(state_get 'PREF_DISTRO')"
    case "$saved_distro" in
      debian10|debian11|debian12|debian13|ubuntu22|ubuntu24)
        DISTRO_ID="$saved_distro"
        PREF_DISTRO_LOADED='1'
        ;;
      esac
  fi

  : "${PREF_LANG_LOADED}" "${PREF_DISTRO_LOADED}"
}

persist_preferences() {
  case "$LANG_CHOICE" in
    zh|en) state_set 'PREF_LANG' "$LANG_CHOICE" ;;
  esac
  case "$DISTRO_ID" in
    debian10|debian11|debian12|debian13|ubuntu22|ubuntu24) state_set 'PREF_DISTRO' "$DISTRO_ID" ;;
  esac
}

reset_saved_preferences() {
  say '将清空已记住的语言和系统，下次启动会重新询问。' 'This clears saved language and distro. You will be asked again next launch.'
  if ! confirm '确认清空？[y/N]' 'Confirm reset? [y/N]'; then
    return 2
  fi

  if [ -f "$STATE_FILE" ]; then
    sed -i -E '/^PREF_LANG=/d;/^PREF_DISTRO=/d' "$STATE_FILE"
  fi
  say '已清空已记住的语言/系统。' 'Saved language/distro has been cleared.'
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
  local detected=''
  local use_detect=''
  detected="$(detect_current_distro)"

  if [ -n "$detected" ]; then
    say "自动检测到系统：$detected" "Detected system: $detected"
    ask '是否使用该检测结果？[Y/n]（回车默认使用）:' 'Use detected system? [Y/n] (Enter for yes):' use_detect
    case "$use_detect" in
      ''|y|Y|yes|YES)
      DISTRO_ID="$detected"
      return 0
      ;;
    esac
  fi

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

detect_current_distro() {
  if [ ! -r /etc/os-release ]; then
    printf '%s' ''
    return 0
  fi

  local os_id os_ver major mapped
  os_id="$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release)"
  os_ver="$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release)"
  major="${os_ver%%.*}"
  mapped=''

  case "$os_id" in
    debian) mapped="debian${major}" ;;
    ubuntu) mapped="ubuntu${major}" ;;
  esac

  case "$mapped" in
    debian10|debian11|debian12|debian13|ubuntu22|ubuntu24)
      printf '%s' "$mapped"
      ;;
    *)
      printf '%s' ''
      ;;
  esac
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
