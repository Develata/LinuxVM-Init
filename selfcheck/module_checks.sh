#!/usr/bin/env bash

: "${BASE_DIR:?}"

check_required_files() {
  check_file_exists "$BASE_DIR/vps-init.sh"
  check_file_exists "$BASE_DIR/lib/common.sh"
  check_file_exists "$BASE_DIR/modules/panel_main.sh"
  check_file_exists "$BASE_DIR/modules/network_stack.sh"
  check_file_exists "$BASE_DIR/modules/firewall.sh"
  check_file_exists "$BASE_DIR/modules/firewall/common.sh"
  check_file_exists "$BASE_DIR/modules/firewall/iptables_mode.sh"
  check_file_exists "$BASE_DIR/modules/firewall/nftables_render.sh"
  check_file_exists "$BASE_DIR/modules/safe_mode.sh"
  check_file_exists "$BASE_DIR/modules/snapshot.sh"
  check_file_exists "$BASE_DIR/modules/monitor.sh"
}

check_shell_syntax() {
  if bash -n "$BASE_DIR/vps-init.sh" "$BASE_DIR/lib/common.sh" "$BASE_DIR"/modules/*.sh "$BASE_DIR"/modules/firewall/*.sh "$BASE_DIR/selfcheck.sh" "$BASE_DIR"/selfcheck/*.sh; then
    ok 'shell syntax check passed'
  else
    fail 'shell syntax check failed'
  fi
}

check_shellcheck() {
  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x -e SC1091,SC2016 "$BASE_DIR"/install.sh "$BASE_DIR"/vps-init.sh "$BASE_DIR"/uninstall.sh "$BASE_DIR"/selfcheck.sh "$BASE_DIR"/selfcheck/*.sh "$BASE_DIR"/lib/*.sh "$BASE_DIR"/modules/*.sh "$BASE_DIR"/modules/firewall/*.sh; then
      ok 'shellcheck passed'
    else
      fail 'shellcheck failed'
    fi
  else
    warn 'command missing: shellcheck'
  fi
}

check_module_sources() {
  if source "$BASE_DIR/lib/common.sh" \
    && source "$BASE_DIR/modules/system.sh" \
    && source "$BASE_DIR/modules/tools.sh" \
    && source "$BASE_DIR/modules/users.sh" \
    && source "$BASE_DIR/modules/network_stack.sh" \
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
}

check_required_functions() {
  local fn
  local required_functions='main_menu init_flow ssh_manage docker_manage firewall_manage nftables_setup network_stack_refresh fail2ban_manage novice_safe_repair snapshot_create monitor_manage script_update'
  for fn in $required_functions; do
    if declare -F "$fn" >/dev/null 2>&1; then
      ok "function available: $fn"
    else
      fail "missing function: $fn"
    fi
  done
}

check_required_commands() {
  local cmd
  for cmd in bash awk sed systemctl; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ok "command available: $cmd"
    else
      warn "command missing: $cmd"
    fi
  done
}
