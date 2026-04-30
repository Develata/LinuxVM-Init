#!/usr/bin/env bash

nftables_detect_iptables_command_frontend() {
  local cmd="$1"
  local version
  if ! is_installed "$cmd"; then
    printf '%s\n' 'missing'
    return
  fi

  version="$("$cmd" --version 2>/dev/null || true)"
  case "$version" in
    *nf_tables*) printf '%s\n' 'nft' ;;
    *legacy*) printf '%s\n' 'legacy' ;;
    *) printf '%s\n' 'unknown' ;;
  esac
}

nftables_detect_iptables_frontend() {
  local ipv4 ipv6
  ipv4="$(nftables_detect_iptables_command_frontend iptables)"
  ipv6="$(nftables_detect_iptables_command_frontend ip6tables)"

  if [ "$ipv4" = 'missing' ] && [ "$ipv6" = 'missing' ]; then
    printf '%s\n' 'missing'
  elif [ "$ipv4" = "$ipv6" ]; then
    printf '%s\n' "$ipv4"
  elif [ "$ipv4" = 'missing' ]; then
    printf '%s\n' "$ipv6"
  elif [ "$ipv6" = 'missing' ]; then
    printf '%s\n' "$ipv4"
  else
    printf '%s\n' 'mixed'
  fi
}

nftables_refresh_iptables_frontend_state() {
  local frontend
  frontend="$(nftables_detect_iptables_frontend)"
  state_set 'FIREWALL_IPTABLES_FRONTEND' "$frontend"
  printf '%s\n' "$frontend"
}

nftables_iptables_save_has_rules() {
  local cmd="$1"
  if ! is_installed "$cmd"; then
    return 1
  fi

  "$cmd" 2>/dev/null | awk '
    /^-[AINR]/ { found = 1 }
    /^:(INPUT|FORWARD|OUTPUT)[[:space:]]/ && $2 != "ACCEPT" { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

nftables_persistent_iptables_files_exist() {
  [ -f /etc/iptables/rules.v4 ] || [ -f /etc/iptables/rules.v6 ]
}

nftables_iptables_legacy_risk_detected() {
  local frontend
  frontend="$(nftables_detect_iptables_frontend)"
  [ "$frontend" = 'legacy' ] || [ "$frontend" = 'mixed' ]
}

nftables_iptables_saved_rules_detected() {
  nftables_persistent_iptables_files_exist \
    || nftables_iptables_save_has_rules iptables-save \
    || nftables_iptables_save_has_rules ip6tables-save
}

nftables_iptables_filter_table_detected() {
  if ! is_installed nft; then
    return 1
  fi

  nft list ruleset 2>/dev/null | awk '
    $1 == "table" && ($2 == "ip" || $2 == "ip6") && $3 == "filter" { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

firewall_effective_mode() {
  local mode
  mode="$(state_get 'FIREWALL_MODE')"
  if [ "$mode" = 'iptables' ]; then
    if nftables_iptables_saved_rules_detected || nftables_iptables_filter_table_detected; then
      printf '%s\n' 'iptables'
      return
    fi
    if nftables_managed_active; then
      printf '%s\n' 'nftables'
      return
    fi
    printf '%s\n' 'iptables'
    return
  fi
  if [ "$mode" = 'nftables' ]; then
    if nftables_managed_active; then
      printf '%s\n' 'nftables'
      return
    fi
    if nftables_iptables_saved_rules_detected || nftables_iptables_filter_table_detected; then
      printf '%s\n' 'iptables'
      return
    fi
  fi

  if nftables_managed_active; then
    printf '%s\n' 'nftables'
  elif nftables_iptables_saved_rules_detected || nftables_iptables_filter_table_detected; then
    printf '%s\n' 'iptables'
  else
    printf '%s\n' 'nftables'
  fi
}

nftables_external_ruleset_detected() {
  if ! is_installed nft; then
    return 1
  fi

  nft list ruleset 2>/dev/null | awk -v family="$NFTABLES_FAMILY" -v table="$NFTABLES_TABLE" '
    $1 == "table" && !($2 == family && $3 == table) { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

nftables_warn_external_rules() {
  if nftables_iptables_saved_rules_detected || nftables_external_ruleset_detected; then
    say '风险提示：检测到脚本管理表之外的 iptables-nft/nftables 规则。iptables-nft 与 nftables 兼容，但其他 base chain 的 DROP 仍可能拦截已在 linuxvm_init 中放行的流量，请用 nft list ruleset 复查。' 'Warning: iptables-nft/nftables rules outside the managed table were detected. iptables-nft is compatible with nftables, but DROP rules in other base chains can still block traffic allowed by linuxvm_init; review nft list ruleset.'
  fi
}

nftables_show_compat_state() {
  local frontend legacy_risk persistent_rules saved_rules external_rules
  frontend="$(nftables_refresh_iptables_frontend_state)"
  legacy_risk='no'
  persistent_rules='no'
  saved_rules='no'
  external_rules='no'

  if nftables_iptables_legacy_risk_detected; then
    legacy_risk='yes'
  fi
  if nftables_persistent_iptables_files_exist; then
    persistent_rules='yes'
  fi
  if nftables_iptables_saved_rules_detected; then
    saved_rules='yes'
  fi
  if nftables_external_ruleset_detected; then
    external_rules='yes'
  fi

  printf 'FIREWALL_IPTABLES_FRONTEND=%s\n' "$frontend"
  printf 'FIREWALL_EFFECTIVE_MODE=%s\n' "$(firewall_effective_mode)"
  printf 'IPTABLES_LEGACY_RISK=%s\n' "$legacy_risk"
  printf 'IPTABLES_PERSISTENT_RULE_FILES=%s\n' "$persistent_rules"
  printf 'IPTABLES_SAVED_RULES_DETECTED=%s\n' "$saved_rules"
  printf 'EXTERNAL_NFT_TABLES_DETECTED=%s\n' "$external_rules"
  if [ "$frontend" = 'nft' ]; then
    say 'iptables-nft 兼容 nftables，无需禁用；IPv6/双栈规则仍由 nftables 原生 inet 表覆盖。' 'iptables-nft is compatible with nftables and does not need to be disabled; IPv6/dual-stack rules remain covered by the native nftables inet table.'
  fi
}
nftables_managed_active() {
  if is_installed nft && nft list table "$NFTABLES_FAMILY" "$NFTABLES_TABLE" >/dev/null 2>&1; then
    return 0
  fi
  grep -q "table ${NFTABLES_FAMILY} ${NFTABLES_TABLE}" "$NFTABLES_CONF" 2>/dev/null
}
