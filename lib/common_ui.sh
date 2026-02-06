#!/usr/bin/env bash

say() {
  local zh="$1"
  local en="$2"
  if [ "$LANG_CHOICE" = 'zh' ]; then
    printf '%s\n' "$zh"
  else
    printf '%s\n' "$en"
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
  printf '%s ' "$prompt"
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
    printf '%s ' "$prompt"
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
