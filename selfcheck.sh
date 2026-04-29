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
    ok "file exists: ${file#"$BASE_DIR"/}"
  else
    fail "missing file: ${file#"$BASE_DIR"/}"
  fi
}

printf 'LinuxVM-Init selfcheck\n'
printf 'Root path: %s\n\n' "$BASE_DIR"

check_file_exists "$BASE_DIR/vps-init.sh"
check_file_exists "$BASE_DIR/lib/common.sh"
check_file_exists "$BASE_DIR/modules/panel_main.sh"
check_file_exists "$BASE_DIR/modules/firewall.sh"
check_file_exists "$BASE_DIR/modules/safe_mode.sh"
check_file_exists "$BASE_DIR/modules/snapshot.sh"
check_file_exists "$BASE_DIR/modules/monitor.sh"

if bash -n "$BASE_DIR/vps-init.sh" "$BASE_DIR/lib/common.sh" "$BASE_DIR"/modules/*.sh "$BASE_DIR/selfcheck.sh"; then
  ok 'shell syntax check passed'
else
  fail 'shell syntax check failed'
fi

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x -e SC1091,SC2016 "$BASE_DIR"/install.sh "$BASE_DIR"/vps-init.sh "$BASE_DIR"/uninstall.sh "$BASE_DIR"/selfcheck.sh "$BASE_DIR"/lib/*.sh "$BASE_DIR"/modules/*.sh; then
    ok 'shellcheck passed'
  else
    fail 'shellcheck failed'
  fi
else
  warn 'command missing: shellcheck'
fi

if source "$BASE_DIR/lib/common.sh" \
  && source "$BASE_DIR/modules/system.sh" \
  && source "$BASE_DIR/modules/tools.sh" \
  && source "$BASE_DIR/modules/users.sh" \
  && source "$BASE_DIR/modules/ssh_common.sh" \
  && source "$BASE_DIR/modules/protocol_ssh.sh" \
  && source "$BASE_DIR/modules/protocol_http.sh" \
  && source "$BASE_DIR/modules/protocol_https.sh" \
  && source "$BASE_DIR/modules/ssh_port.sh" \
  && source "$BASE_DIR/modules/ssh_auth.sh" \
  && source "$BASE_DIR/modules/ssh_manage.sh" \
  && source "$BASE_DIR/modules/snapshot.sh" \
  && source "$BASE_DIR/modules/firewall.sh" \
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

check_nftables_ruleset_generation() {
  local tmp_file
  tmp_file="$(mktemp /tmp/linuxvm-init-selfcheck-nftables.XXXXXX)" || {
    fail 'failed to create nftables selfcheck temp file'
    return
  }

  if nftables_render_ruleset "$tmp_file" 34521 '2001:db8::1' '80,443' '53' 'essential' 'docker'; then
    ok 'nftables ruleset renders successfully'
  else
    fail 'nftables ruleset render failed'
    rm -f "$tmp_file"
    return
  fi

  if command -v nft >/dev/null 2>&1; then
    if nft -c -f "$tmp_file"; then
      ok 'nftables ruleset syntax check passed'
    else
      fail 'nftables ruleset syntax check failed'
    fi
  else
    warn 'command missing: nft'
  fi

  rm -f "$tmp_file"
}

check_nftables_ruleset_generation

write_mock_iptables_command() {
  local dir="$1"
  local cmd="$2"
  local backend="$3"
  if [ "$backend" = 'missing' ]; then
    return
  fi

  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'if [ "${1:-}" = "--version" ]; then'
    printf "  printf 'iptables v1.8.10 (%%s)\\n' '%s'\n" "$backend"
    printf '%s\n' '  exit 0'
    printf '%s\n' 'fi'
    printf '%s\n' 'exit 0'
  } >"$dir/$cmd"
  chmod +x "$dir/$cmd"
}

check_iptables_frontend_case() {
  local label="$1"
  local ipv4_backend="$2"
  local ipv6_backend="$3"
  local expected="$4"
  local tmpbin old_path result
  tmpbin="$(mktemp -d /tmp/linuxvm-init-selfcheck-iptables.XXXXXX)" || {
    fail "failed to create iptables frontend selfcheck temp dir: $label"
    return
  }

  write_mock_iptables_command "$tmpbin" iptables "$ipv4_backend"
  write_mock_iptables_command "$tmpbin" ip6tables "$ipv6_backend"
  old_path="$PATH"
  PATH="$tmpbin"
  result="$(nftables_detect_iptables_frontend)"
  PATH="$old_path"
  rm -rf "$tmpbin"

  if [ "$result" = "$expected" ]; then
    ok "iptables frontend detection: $label"
  else
    fail "iptables frontend detection: $label expected $expected got $result"
  fi
}

check_iptables_frontend_detection() {
  check_iptables_frontend_case 'nf_tables' 'nf_tables' 'nf_tables' 'nft'
  check_iptables_frontend_case 'legacy' 'legacy' 'legacy' 'legacy'
  check_iptables_frontend_case 'mixed' 'nf_tables' 'legacy' 'mixed'
  check_iptables_frontend_case 'missing' 'missing' 'missing' 'missing'
}

check_iptables_frontend_detection

required_functions='main_menu init_flow ssh_manage docker_manage firewall_manage nftables_setup fail2ban_manage novice_safe_repair snapshot_create monitor_manage script_update'
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
