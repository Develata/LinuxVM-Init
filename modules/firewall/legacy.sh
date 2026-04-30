#!/usr/bin/env bash

nftables_legacy_firewall_detected() {
  if is_installed ufw && ufw status 2>/dev/null | grep -q 'Status: active'; then
    return 0
  fi
  if nftables_iptables_legacy_risk_detected; then
    return 0
  fi
  if nftables_iptables_saved_rules_detected; then
    return 0
  fi
  if is_installed nft \
    && ! nft list table "$NFTABLES_FAMILY" "$NFTABLES_TABLE" >/dev/null 2>&1 \
    && nft list ruleset 2>/dev/null | grep -q '^table '; then
    return 0
  fi
  if nftables_external_ruleset_detected; then
    return 0
  fi
  if systemctl is-enabled netfilter-persistent >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

nftables_backup_legacy_firewalls() {
  ensure_state_dirs
  local ts dir
  ts="$(date +%Y%m%d-%H%M%S)"
  dir="$NFTABLES_LEGACY_BACKUP_ROOT/$ts"
  mkdir -p "$dir"

  nftables_detect_iptables_frontend >"$dir/iptables_frontend.txt" 2>&1 || true
  if is_installed iptables; then
    iptables --version >"$dir/iptables_version.txt" 2>&1 || true
    iptables -S >"$dir/iptables-S.v4" 2>"$dir/iptables-S.v4.err" || true
  fi
  if is_installed ip6tables; then
    ip6tables --version >"$dir/ip6tables_version.txt" 2>&1 || true
    ip6tables -S >"$dir/ip6tables-S.v6" 2>"$dir/ip6tables-S.v6.err" || true
  fi
  if is_installed update-alternatives; then
    update-alternatives --display iptables >"$dir/update-alternatives-iptables.txt" 2>&1 || true
    update-alternatives --display ip6tables >"$dir/update-alternatives-ip6tables.txt" 2>&1 || true
  fi
  if is_installed ufw; then
    ufw status verbose >"$dir/ufw_status_verbose.txt" 2>&1 || true
    ufw status numbered >"$dir/ufw_status_numbered.txt" 2>&1 || true
  fi
  if is_installed iptables-save; then
    iptables-save >"$dir/iptables-save.v4" 2>"$dir/iptables-save.v4.err" || true
  fi
  if is_installed ip6tables-save; then
    ip6tables-save >"$dir/ip6tables-save.v6" 2>"$dir/ip6tables-save.v6.err" || true
  fi
  if is_installed nft; then
    nft list ruleset >"$dir/nft-list-ruleset.txt" 2>"$dir/nft-list-ruleset.err" || true
  fi
  [ -f /etc/iptables/rules.v4 ] && cp /etc/iptables/rules.v4 "$dir/rules.v4"
  [ -f /etc/iptables/rules.v6 ] && cp /etc/iptables/rules.v6 "$dir/rules.v6"
  [ -f /etc/ufw/user.rules ] && cp /etc/ufw/user.rules "$dir/ufw_user.rules"
  [ -f /etc/ufw/user6.rules ] && cp /etc/ufw/user6.rules "$dir/ufw_user6.rules"
  [ -f "$STATE_FILE" ] && cp "$STATE_FILE" "$dir/state.env"

  printf 'time=%s\n' "$ts" >"$dir/meta"
  printf 'iptables_frontend=%s\n' "$(cat "$dir/iptables_frontend.txt" 2>/dev/null || printf '%s' 'missing')" >>"$dir/meta"
  state_set 'LAST_LEGACY_FIREWALL_BACKUP' "$dir"
  say "旧防火墙规则已保存：$dir" "Legacy firewall rules saved: $dir"
}

nftables_disable_legacy_firewalls() {
  if is_installed ufw && ufw status 2>/dev/null | grep -q 'Status: active'; then
    run_cmd 'ufw --force disable'
  fi
  run_cmd 'systemctl disable --now ufw 2>/dev/null || true'
  run_cmd 'systemctl disable --now netfilter-persistent 2>/dev/null || true'
}
