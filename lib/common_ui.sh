#!/usr/bin/env bash

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_CYAN='\033[36m'
  C_YELLOW='\033[33m'
  C_GREEN='\033[32m'
  C_BLUE='\033[34m'
else
  C_RESET=''
  C_BOLD=''
  C_CYAN=''
  C_YELLOW=''
  C_GREEN=''
  C_BLUE=''
fi

style_line() {
  local text="$1"
  case "$text" in
    '==== '*|'===='* ) printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "$text" "$C_RESET" ;;
    风险提示*|Warning:* ) printf '%b%s%b\n' "${C_BOLD}${C_YELLOW}" "$text" "$C_RESET" ;;
    已*|*' completed.' ) printf '%b%s%b\n' "${C_GREEN}" "$text" "$C_RESET" ;;
    *) printf '%s\n' "$text" ;;
  esac
}

say() {
  local zh="$1"
  local en="$2"
  if [ "$LANG_CHOICE" = 'zh' ]; then
    style_line "$zh"
  else
    style_line "$en"
  fi
}

confirm() {
  local zh="$1"
  local en="$2"
  local prompt
  if [ "$LANG_CHOICE" = 'zh' ]; then
    prompt="$zh"
  else
    prompt="$en"
  fi
  if [ "$NON_INTERACTIVE" = '1' ]; then
    if [ "$NI_AUTO_YES" = '1' ]; then
      return 0
    fi
    return 1
  fi
  printf '%b%s%b ' "${C_BOLD}${C_BLUE}" "$prompt" "$C_RESET"
  read -r ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

ask() {
  local zh="$1"
  local en="$2"
  local var_name="$3"
  local prompt
  local value
  if [ "$LANG_CHOICE" = 'zh' ]; then
    prompt="$zh"
  else
    prompt="$en"
  fi
  if [ "$NON_INTERACTIVE" = '1' ]; then
    local ni_key="NI_${var_name}"
    value="${!ni_key:-}"
  else
    printf '%b%s%b ' "${C_BOLD}${C_BLUE}" "$prompt" "$C_RESET"
    read -r value
  fi
  printf -v "$var_name" '%s' "$value"
}

pause() {
  if [ "$NON_INTERACTIVE" = '1' ]; then
    return
  fi
  say '按回车继续...' 'Press Enter to continue...'
  read -r _
}
