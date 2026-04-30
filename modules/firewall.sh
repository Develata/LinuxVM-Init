#!/usr/bin/env bash

NFTABLES_TABLE='linuxvm_init'
NFTABLES_FAMILY='inet'
NFTABLES_CONF='/etc/nftables.conf'
NFTABLES_LEGACY_BACKUP_ROOT='/etc/linuxvm-init/legacy-firewall-backups'

detect_ssh_port_for_firewall() {
  local ssh_port
  ssh_port="$(effective_ssh_port)"
  if ! is_valid_port "$ssh_port"; then
    say '检测 SSH 端口失败，已取消防火墙设置。' 'Failed to detect SSH port, firewall setup canceled.'
    return 1
  fi

  if is_port_in_use "$ssh_port"; then
    say "已检测到 SSH 端口: ${ssh_port}" "Detected SSH port: ${ssh_port}"
  else
    say "检测到 SSH 端口: ${ssh_port}（当前监听未确认，请谨慎）" "Detected SSH port: ${ssh_port} (listener not confirmed, proceed carefully)"
  fi
  FIREWALL_SSH_PORT="$ssh_port"
  state_set 'FIREWALL_SSH_PORT' "$ssh_port"
}

nftables_install() {
  if is_installed nft; then
    return 0
  fi

  say '未检测到 nftables，正在安装。' 'nftables not found, installing.'
  run_cmd 'DEBIAN_FRONTEND=noninteractive apt install -y nftables'
}

nftables_normalize_port_list() {
  local raw="$1"
  local port normalized=''
  for port in $(printf '%s' "$raw" | tr ',' ' '); do
    if is_valid_port "$port" && ! printf ',%s,' "$normalized" | grep -q ",${port},"; then
      normalized="${normalized}${normalized:+,}${port}"
    fi
  done
  printf '%s\n' "$normalized"
}

nftables_allowed_ports() {
  nftables_normalize_port_list "$(state_get 'FIREWALL_ALLOWED_TCP_PORTS')"
}

nftables_allowed_udp_ports() {
  nftables_normalize_port_list "$(state_get 'FIREWALL_ALLOWED_UDP_PORTS')"
}

nftables_icmp_allowed() {
  [ "$(nftables_icmp_mode)" != 'off' ]
}

nftables_icmp_mode_normalize() {
  local mode="${1:-}"
  case "$mode" in
    1|essential) printf '%s\n' 'essential' ;;
    all) printf '%s\n' 'all' ;;
    0|off|'') printf '%s\n' 'off' ;;
    *) printf '%s\n' 'off' ;;
  esac
}

nftables_icmp_mode() {
  local mode legacy
  mode="$(state_get 'FIREWALL_ICMP_MODE')"
  if [ -n "$mode" ]; then
    nftables_icmp_mode_normalize "$mode"
    return
  fi

  legacy="$(state_get 'FIREWALL_ALLOW_ICMP')"
  if [ "$legacy" = '1' ]; then
    printf '%s\n' 'essential'
  else
    printf '%s\n' 'off'
  fi
}

nftables_forward_mode_normalize() {
  local mode="${1:-}"
  case "$mode" in
    strict) printf '%s\n' 'strict' ;;
    docker|'') printf '%s\n' 'docker' ;;
    *) printf '%s\n' 'docker' ;;
  esac
}

nftables_forward_mode() {
  nftables_forward_mode_normalize "$(state_get 'FIREWALL_FORWARD_MODE')"
}

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

nftables_setup_icmp_mode() {
  local mode legacy
  mode="$(state_get 'FIREWALL_ICMP_MODE')"
  if [ -n "$mode" ]; then
    nftables_icmp_mode_normalize "$mode"
    return
  fi

  legacy="$(state_get 'FIREWALL_ALLOW_ICMP')"
  if [ -n "$legacy" ]; then
    nftables_icmp_mode_normalize "$legacy"
  else
    printf '%s\n' 'essential'
  fi
}

nftables_render_tcp_accept_rule() {
  local stack="$1"
  local port="$2"
  local comment="$3"
  case "$(network_stack_normalize "$stack")" in
    ipv4) printf '    meta nfproto ipv4 tcp dport %s accept comment "%s"\n' "$port" "$comment" ;;
    ipv6) printf '    meta nfproto ipv6 tcp dport %s accept comment "%s"\n' "$port" "$comment" ;;
    *) printf '    tcp dport %s accept comment "%s"\n' "$port" "$comment" ;;
  esac
}

nftables_render_udp_accept_rule() {
  local stack="$1"
  local port="$2"
  local comment="$3"
  case "$(network_stack_normalize "$stack")" in
    ipv4) printf '    meta nfproto ipv4 udp dport %s accept comment "%s"\n' "$port" "$comment" ;;
    ipv6) printf '    meta nfproto ipv6 udp dport %s accept comment "%s"\n' "$port" "$comment" ;;
    *) printf '    udp dport %s accept comment "%s"\n' "$port" "$comment" ;;
  esac
}

nftables_render_icmp_rules() {
  local mode stack
  mode="$(nftables_icmp_mode_normalize "$1")"
  stack="$(network_stack_normalize "${2:-unknown}")"
  case "$mode" in
    essential)
      if network_stack_supports_ipv4 "$stack"; then
        printf '    meta l4proto icmp icmp type { echo-request, destination-unreachable, time-exceeded, parameter-problem } accept comment "linuxvm-init:icmp-essential-v4"\n'
      fi
      if network_stack_supports_ipv6 "$stack"; then
        printf '    meta l4proto icmpv6 icmpv6 type { echo-request, destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept comment "linuxvm-init:icmp-essential-v6"\n'
      fi
      ;;
    all)
      if network_stack_supports_ipv4 "$stack"; then
        printf '    meta l4proto icmp accept comment "linuxvm-init:icmp-all-v4"\n'
      fi
      if network_stack_supports_ipv6 "$stack"; then
        printf '    meta l4proto icmpv6 accept comment "linuxvm-init:icmp-all-v6"\n'
      fi
      ;;
  esac
}

nftables_render_forward_rules() {
  local mode
  mode="$(nftables_forward_mode_normalize "$1")"
  if [ "$mode" = 'docker' ]; then
    printf '    ct state established,related accept comment "linuxvm-init:forward-established"\n'
    printf '    iifname "docker0" accept comment "linuxvm-init:forward-docker0-in"\n'
    printf '    oifname "docker0" accept comment "linuxvm-init:forward-docker0-out"\n'
    printf '    iifname "br-*" accept comment "linuxvm-init:forward-docker-bridge-in"\n'
    printf '    oifname "br-*" accept comment "linuxvm-init:forward-docker-bridge-out"\n'
  fi
}

nftables_state_add_port() {
  local port="$1"
  local ports
  ports="$(nftables_allowed_ports)"
  ports="$(nftables_normalize_port_list "${ports}${ports:+,}${port}")"
  state_set 'FIREWALL_ALLOWED_TCP_PORTS' "$ports"
}

nftables_state_add_udp_port() {
  local port="$1"
  local ports
  ports="$(nftables_allowed_udp_ports)"
  ports="$(nftables_normalize_port_list "${ports}${ports:+,}${port}")"
  state_set 'FIREWALL_ALLOWED_UDP_PORTS' "$ports"
}

nftables_state_remove_port() {
  local remove_port="$1"
  local port ports=''
  for port in $(printf '%s' "$(nftables_allowed_ports)" | tr ',' ' '); do
    if [ "$port" != "$remove_port" ]; then
      ports="${ports}${ports:+,}${port}"
    fi
  done
  state_set 'FIREWALL_ALLOWED_TCP_PORTS' "$ports"
}

nftables_state_remove_udp_port() {
  local remove_port="$1"
  local port ports=''
  for port in $(printf '%s' "$(nftables_allowed_udp_ports)" | tr ',' ' '); do
    if [ "$port" != "$remove_port" ]; then
      ports="${ports}${ports:+,}${port}"
    fi
  done
  state_set 'FIREWALL_ALLOWED_UDP_PORTS' "$ports"
}

iptables_mode_command_for_family() {
  case "$1" in
    ipv4) printf '%s\n' 'iptables' ;;
    ipv6) printf '%s\n' 'ip6tables' ;;
    *) return 1 ;;
  esac
}

iptables_mode_insert_position() {
  local cmd="$1"
  local pos
  pos="$("$cmd" -nvL INPUT --line-numbers 2>/dev/null | awk '$0 ~ /f2b-sshd/ { line = $1 } END { if (line) print line + 1; else print 1 }')"
  case "$pos" in
    ''|*[!0-9]*) printf '%s\n' '1' ;;
    *) printf '%s\n' "$pos" ;;
  esac
}

iptables_mode_rule_exists() {
  local cmd="$1"
  shift
  "$cmd" -C INPUT "$@" >/dev/null 2>&1
}

iptables_mode_persistence_available() {
  [ -e /etc/iptables/rules.v4 ] || [ -e /etc/iptables/rules.v6 ] \
    || { is_installed systemctl && systemctl is-enabled netfilter-persistent >/dev/null 2>&1; }
}

iptables_mode_persist_rules() {
  local stack="${1:-}"
  local saved='0'
  local failed='0'
  local need_v4='0'
  local need_v6='0'
  if [ -z "$stack" ]; then
    stack="$(state_get 'NETWORK_STACK')"
  fi
  if [ -z "$stack" ] || [ "$stack" = 'unknown' ]; then
    stack="$(network_stack_refresh)"
  fi
  stack="$(network_stack_normalize "$stack")"

  if ! iptables_mode_persistence_available; then
    state_set 'FIREWALL_IPTABLES_PERSISTENCE' 'runtime-only'
    say '风险提示：未检测到 iptables 持久化配置，本次 iptables/ip6tables 规则可能在重启后丢失。' 'Warning: iptables/ip6tables persistence was not detected; these rules may be lost after reboot.'
    return 0
  fi

  if network_stack_supports_ipv4 "$stack"; then
    need_v4='1'
  fi
  if network_stack_supports_ipv6 "$stack"; then
    need_v6='1'
  fi
  if [ "$need_v4" != '1' ] && [ "$need_v6" != '1' ]; then
    state_set 'FIREWALL_IPTABLES_PERSISTENCE' 'runtime-only'
    say '风险提示：未检测到匹配当前网络栈的 iptables 持久化目标。' 'Warning: no iptables persistence target matched the current network stack.'
    return 0
  fi

  mkdir -p /etc/iptables
  if [ "$need_v4" = '1' ]; then
    if ! is_installed iptables-save; then
      failed='1'
    elif iptables-save >/etc/iptables/rules.v4; then
      saved='1'
    else
      failed='1'
    fi
  fi
  if [ "$need_v6" = '1' ]; then
    if ! is_installed ip6tables-save; then
      failed='1'
    elif ip6tables-save >/etc/iptables/rules.v6; then
      saved='1'
    else
      failed='1'
    fi
  fi
  if [ "$failed" = '1' ]; then
    state_set 'FIREWALL_IPTABLES_PERSISTENCE' 'failed'
    say 'iptables/ip6tables 规则保存失败，请检查 /etc/iptables 权限、磁盘空间或 iptables-save 输出。' 'Failed to persist iptables/ip6tables rules; check /etc/iptables permissions, disk space, or iptables-save output.'
    return 1
  fi
  if [ "$saved" = '1' ]; then
    state_set 'FIREWALL_IPTABLES_PERSISTENCE' 'saved'
    say 'iptables/ip6tables 规则已保存到当前网络栈对应的 /etc/iptables/rules.v4 或 rules.v6。' 'iptables/ip6tables rules saved to the matching /etc/iptables/rules.v4 or rules.v6 file for the current network stack.'
  fi
}

iptables_mode_warn_existing_wide_ssh_rule() {
  local port="$1"
  local source_ip="$2"
  local stack="$3"
  local warned='0'
  if is_valid_ipv4 "$source_ip" && network_stack_supports_ipv4 "$stack" && is_installed iptables; then
    if iptables_mode_rule_exists iptables -p tcp --dport "$port" -m comment --comment "linuxvm-init:tcp-${port}" -j ACCEPT \
      || iptables_mode_rule_exists iptables -p tcp --dport "$port" -j ACCEPT; then
      warned='1'
    fi
  elif is_valid_ipv6 "$source_ip" && network_stack_supports_ipv6 "$stack" && is_installed ip6tables; then
    if iptables_mode_rule_exists ip6tables -p tcp --dport "$port" -m comment --comment "linuxvm-init:tcp-${port}" -j ACCEPT \
      || iptables_mode_rule_exists ip6tables -p tcp --dport "$port" -j ACCEPT; then
      warned='1'
    fi
  fi

  if [ "$warned" = '1' ]; then
    say '风险提示：检测到同端口已有全来源放行规则；本次只新增来源白名单，不会自动收紧已有规则。' 'Warning: an existing broad allow rule for the same port was detected; this only adds a source allow rule and does not tighten existing rules.'
  fi
}

iptables_mode_add_input_rule() {
  local family="$1"
  shift
  local cmd pos
  cmd="$(iptables_mode_command_for_family "$family")" || return 1
  if ! is_installed "$cmd"; then
    say "${cmd} 未安装，无法添加 ${family} 规则。" "${cmd} is not installed; cannot add ${family} rule."
    return 1
  fi

  if iptables_mode_rule_exists "$cmd" "$@"; then
    return 0
  fi
  pos="$(iptables_mode_insert_position "$cmd")"
  run_argv "$cmd" -I INPUT "$pos" "$@"
}

iptables_mode_delete_input_rule() {
  local family="$1"
  shift
  local cmd deleted='0'
  cmd="$(iptables_mode_command_for_family "$family")" || return 1
  if ! is_installed "$cmd"; then
    say "${cmd} 未安装，跳过 ${family} 规则。" "${cmd} is not installed; skipping ${family} rule."
    return 0
  fi

  while iptables_mode_rule_exists "$cmd" "$@"; do
    run_argv "$cmd" -D INPUT "$@" || return 1
    deleted='1'
  done
  if [ "$deleted" != '1' ]; then
    say "${cmd} 中未找到对应的 linuxvm-init 规则，跳过。" "No matching linuxvm-init rule found in ${cmd}; skipping."
  fi
  return 0
}

iptables_mode_for_each_enabled_family() {
  local stack="$1"
  local fn="$2"
  shift 2
  local rc=0
  stack="$(network_stack_normalize "$stack")"
  if network_stack_supports_ipv4 "$stack"; then
    "$fn" ipv4 "$@" || rc=1
  fi
  if network_stack_supports_ipv6 "$stack"; then
    "$fn" ipv6 "$@" || rc=1
  fi
  return "$rc"
}

iptables_mode_add_tcp_port() {
  local port="$1"
  local stack="$2"
  iptables_mode_for_each_enabled_family "$stack" iptables_mode_add_input_rule -p tcp --dport "$port" -m comment --comment "linuxvm-init:tcp-${port}" -j ACCEPT
}

iptables_mode_add_udp_port() {
  local port="$1"
  local stack="$2"
  iptables_mode_for_each_enabled_family "$stack" iptables_mode_add_input_rule -p udp --dport "$port" -m comment --comment "linuxvm-init:udp-${port}" -j ACCEPT
}

iptables_mode_add_tcp_port_from_ip() {
  local port="$1"
  local source_ip="$2"
  local stack="$3"
  if ! is_valid_port "$port" || ! is_valid_ip "$source_ip"; then
    say 'SSH 来源 IP 或端口无效。' 'Invalid SSH source IP or port.'
    return 1
  fi

  if is_valid_ipv4 "$source_ip"; then
    if ! network_stack_supports_ipv4 "$stack"; then
      say '当前网络栈未启用 IPv4，拒绝添加 IPv4 来源白名单。' 'IPv4 is not enabled in the current network stack; refusing IPv4 source allow rule.'
      return 1
    fi
    iptables_mode_warn_existing_wide_ssh_rule "$port" "$source_ip" "$stack"
    iptables_mode_add_input_rule ipv4 -s "$source_ip" -p tcp --dport "$port" -m comment --comment "linuxvm-init:ssh-source-${port}" -j ACCEPT
  else
    if ! network_stack_supports_ipv6 "$stack"; then
      say '当前网络栈未启用 IPv6，拒绝添加 IPv6 来源白名单。' 'IPv6 is not enabled in the current network stack; refusing IPv6 source allow rule.'
      return 1
    fi
    iptables_mode_warn_existing_wide_ssh_rule "$port" "$source_ip" "$stack"
    iptables_mode_add_input_rule ipv6 -s "$source_ip" -p tcp --dport "$port" -m comment --comment "linuxvm-init:ssh-source-${port}" -j ACCEPT
  fi
}

iptables_mode_delete_tcp_port() {
  local port="$1"
  local stack="$2"
  iptables_mode_for_each_enabled_family "$stack" iptables_mode_delete_input_rule -p tcp --dport "$port" -m comment --comment "linuxvm-init:tcp-${port}" -j ACCEPT
}

iptables_mode_delete_udp_port() {
  local port="$1"
  local stack="$2"
  iptables_mode_for_each_enabled_family "$stack" iptables_mode_delete_input_rule -p udp --dport "$port" -m comment --comment "linuxvm-init:udp-${port}" -j ACCEPT
}

iptables_mode_add_icmp_family() {
  local family="$1"
  case "$family" in
    ipv4)
      iptables_mode_add_input_rule ipv4 -p icmp --icmp-type echo-request -m comment --comment 'linuxvm-init:icmp-essential-v4-echo-request' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv4 -p icmp --icmp-type destination-unreachable -m comment --comment 'linuxvm-init:icmp-essential-v4-destination-unreachable' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv4 -p icmp --icmp-type time-exceeded -m comment --comment 'linuxvm-init:icmp-essential-v4-time-exceeded' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv4 -p icmp --icmp-type parameter-problem -m comment --comment 'linuxvm-init:icmp-essential-v4-parameter-problem' -j ACCEPT
      ;;
    ipv6)
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type echo-request -m comment --comment 'linuxvm-init:icmp-essential-v6-echo-request' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type destination-unreachable -m comment --comment 'linuxvm-init:icmp-essential-v6-destination-unreachable' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type packet-too-big -m comment --comment 'linuxvm-init:icmp-essential-v6-packet-too-big' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type time-exceeded -m comment --comment 'linuxvm-init:icmp-essential-v6-time-exceeded' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type parameter-problem -m comment --comment 'linuxvm-init:icmp-essential-v6-parameter-problem' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type router-solicitation -m comment --comment 'linuxvm-init:icmp-essential-v6-router-solicitation' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type router-advertisement -m comment --comment 'linuxvm-init:icmp-essential-v6-router-advertisement' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type neighbor-solicitation -m comment --comment 'linuxvm-init:icmp-essential-v6-neighbor-solicitation' -j ACCEPT || return 1
      iptables_mode_add_input_rule ipv6 -p ipv6-icmp --icmpv6-type neighbor-advertisement -m comment --comment 'linuxvm-init:icmp-essential-v6-neighbor-advertisement' -j ACCEPT
      ;;
  esac
}

iptables_mode_delete_icmp_family() {
  local family="$1"
  case "$family" in
    ipv4)
      iptables_mode_delete_input_rule ipv4 -p icmp --icmp-type echo-request -m comment --comment 'linuxvm-init:icmp-essential-v4-echo-request' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv4 -p icmp --icmp-type destination-unreachable -m comment --comment 'linuxvm-init:icmp-essential-v4-destination-unreachable' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv4 -p icmp --icmp-type time-exceeded -m comment --comment 'linuxvm-init:icmp-essential-v4-time-exceeded' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv4 -p icmp --icmp-type parameter-problem -m comment --comment 'linuxvm-init:icmp-essential-v4-parameter-problem' -j ACCEPT || true
      ;;
    ipv6)
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type echo-request -m comment --comment 'linuxvm-init:icmp-essential-v6-echo-request' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type destination-unreachable -m comment --comment 'linuxvm-init:icmp-essential-v6-destination-unreachable' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type packet-too-big -m comment --comment 'linuxvm-init:icmp-essential-v6-packet-too-big' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type time-exceeded -m comment --comment 'linuxvm-init:icmp-essential-v6-time-exceeded' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type parameter-problem -m comment --comment 'linuxvm-init:icmp-essential-v6-parameter-problem' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type router-solicitation -m comment --comment 'linuxvm-init:icmp-essential-v6-router-solicitation' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type router-advertisement -m comment --comment 'linuxvm-init:icmp-essential-v6-router-advertisement' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type neighbor-solicitation -m comment --comment 'linuxvm-init:icmp-essential-v6-neighbor-solicitation' -j ACCEPT || true
      iptables_mode_delete_input_rule ipv6 -p ipv6-icmp --icmpv6-type neighbor-advertisement -m comment --comment 'linuxvm-init:icmp-essential-v6-neighbor-advertisement' -j ACCEPT || true
      ;;
  esac
}

iptables_mode_allow_rule() {
  local protocol="$1"
  local value="${2:-}"
  local stack
  stack="$(network_stack_refresh)"
  case "$protocol" in
    tcp)
      iptables_mode_add_tcp_port "$value" "$stack" || return 1
      nftables_state_add_port "$value"
      ;;
    udp)
      iptables_mode_add_udp_port "$value" "$stack" || return 1
      nftables_state_add_udp_port "$value"
      ;;
    icmp)
      iptables_mode_for_each_enabled_family "$stack" iptables_mode_add_icmp_family || return 1
      state_set 'FIREWALL_ICMP_MODE' 'essential'
      state_set 'FIREWALL_ALLOW_ICMP' '1'
      ;;
    *) return 1 ;;
  esac
  state_set 'FIREWALL_MODE' 'iptables'
  iptables_mode_persist_rules "$stack"
}

iptables_mode_remove_rule() {
  local protocol="$1"
  local value="${2:-}"
  local stack
  stack="$(network_stack_refresh)"
  case "$protocol" in
    tcp)
      iptables_mode_delete_tcp_port "$value" "$stack" || return 1
      nftables_state_remove_port "$value"
      ;;
    udp)
      iptables_mode_delete_udp_port "$value" "$stack" || return 1
      nftables_state_remove_udp_port "$value"
      ;;
    icmp)
      iptables_mode_for_each_enabled_family "$stack" iptables_mode_delete_icmp_family || return 1
      state_set 'FIREWALL_ICMP_MODE' 'off'
      state_set 'FIREWALL_ALLOW_ICMP' '0'
      ;;
    *) return 1 ;;
  esac
  state_set 'FIREWALL_MODE' 'iptables'
  iptables_mode_persist_rules "$stack"
}

nftables_managed_active() {
  if is_installed nft && nft list table "$NFTABLES_FAMILY" "$NFTABLES_TABLE" >/dev/null 2>&1; then
    return 0
  fi
  grep -q "table ${NFTABLES_FAMILY} ${NFTABLES_TABLE}" "$NFTABLES_CONF" 2>/dev/null
}

nftables_render_ruleset() {
  local output_file="$1"
  local ssh_port="$2"
  local source_ip="${3:-}"
  local allowed_tcp_ports="${4:-}"
  local allowed_udp_ports="${5:-}"
  local icmp_mode="${6:-off}"
  local forward_mode="${7:-docker}"
  local network_stack="${8:-unknown}"
  local port

  network_stack="$(network_stack_normalize "$network_stack")"

  if ! is_valid_port "$ssh_port"; then
    say 'SSH 端口无效，拒绝生成 nftables 规则。' 'Invalid SSH port, refusing to generate nftables rules.'
    return 1
  fi

  {
    printf '%s\n' '#!/usr/sbin/nft -f'
    printf '%s\n' '# Managed by LinuxVM-Init. Manual edits may be overwritten.'
    printf '\n'
    printf 'table %s %s {\n' "$NFTABLES_FAMILY" "$NFTABLES_TABLE"
    printf '  chain input {\n'
    printf '    type filter hook input priority 0; policy drop;\n'
    printf '    iifname "lo" accept comment "linuxvm-init:loopback"\n'
    printf '    ct state established,related accept comment "linuxvm-init:established"\n'
    if [ -n "$source_ip" ] && is_valid_ip "$source_ip"; then
      if is_valid_ipv4 "$source_ip" && network_stack_supports_ipv4 "$network_stack"; then
        printf '    ip saddr %s tcp dport %s accept comment "linuxvm-init:ssh-source"\n' "$source_ip" "$ssh_port"
      elif is_valid_ipv6 "$source_ip" && network_stack_supports_ipv6 "$network_stack"; then
        printf '    ip6 saddr %s tcp dport %s accept comment "linuxvm-init:ssh-source"\n' "$source_ip" "$ssh_port"
      fi
    fi
    nftables_render_tcp_accept_rule "$network_stack" "$ssh_port" 'linuxvm-init:ssh'
    for port in $(printf '%s' "$allowed_tcp_ports" | tr ',' ' '); do
      if is_valid_port "$port" && [ "$port" != "$ssh_port" ]; then
        nftables_render_tcp_accept_rule "$network_stack" "$port" "linuxvm-init:tcp-${port}"
      fi
    done
    for port in $(printf '%s' "$allowed_udp_ports" | tr ',' ' '); do
      if is_valid_port "$port"; then
        nftables_render_udp_accept_rule "$network_stack" "$port" "linuxvm-init:udp-${port}"
      fi
    done
    nftables_render_icmp_rules "$icmp_mode" "$network_stack"
    printf '  }\n'
    printf '\n'
    printf '  chain forward {\n'
    printf '    type filter hook forward priority 0; policy drop;\n'
    nftables_render_forward_rules "$forward_mode"
    printf '  }\n'
    printf '\n'
    printf '  chain output {\n'
    printf '    type filter hook output priority 0; policy accept;\n'
    printf '  }\n'
    printf '}\n'
  } >"$output_file"
}

nftables_validate_ruleset() {
  local rules_file="$1"
  run_argv nft -c -f "$rules_file"
}

nftables_verify_ssh_rule() {
  local ssh_port="$1"
  nft list chain "$NFTABLES_FAMILY" "$NFTABLES_TABLE" input 2>/dev/null | grep -Eq "tcp dport ${ssh_port} .*accept"
}

nftables_restore_managed_table() {
  local table_backup="$1"
  local had_table="$2"

  say '尝试恢复上一份脚本管理的 nftables 表。' 'Trying to restore the previous managed nftables table.'
  nft delete table "$NFTABLES_FAMILY" "$NFTABLES_TABLE" >/dev/null 2>&1 || true
  if [ "$had_table" = '1' ] && [ -s "$table_backup" ]; then
    if nft -f "$table_backup" >/dev/null 2>&1; then
      say '已恢复上一份 nftables 管理表。' 'Restored the previous managed nftables table.'
      return 0
    fi
    say '恢复上一份 nftables 管理表失败，请检查快照或备份。' 'Failed to restore the previous managed nftables table; inspect snapshots or backups.'
    return 1
  fi
  return 0
}

nftables_apply_ruleset_file() {
  local rules_file="$1"
  local ssh_port="$2"
  local previous_table previous_conf had_table had_conf rc
  previous_table="$(mktemp /tmp/linuxvm-init-nftables-prev-table.XXXXXX)" || return 1
  previous_conf="$(mktemp /tmp/linuxvm-init-nftables-prev-conf.XXXXXX)" || {
    rm -f "$previous_table"
    return 1
  }
  had_table='0'
  had_conf='0'

  nftables_validate_ruleset "$rules_file" || {
    rm -f "$previous_table" "$previous_conf"
    return 1
  }
  if nft list table "$NFTABLES_FAMILY" "$NFTABLES_TABLE" >"$previous_table" 2>/dev/null; then
    had_table='1'
  fi
  if [ -f "$NFTABLES_CONF" ]; then
    cp -p "$NFTABLES_CONF" "$previous_conf"
    had_conf='1'
  fi
  backup_file "$NFTABLES_CONF"
  mkdir -p "$(dirname "$NFTABLES_CONF")"
  cp "$rules_file" "$NFTABLES_CONF"

  if nft list table "$NFTABLES_FAMILY" "$NFTABLES_TABLE" >/dev/null 2>&1; then
    if ! run_argv nft delete table "$NFTABLES_FAMILY" "$NFTABLES_TABLE"; then
      if [ "$had_conf" = '1' ]; then
        cp -p "$previous_conf" "$NFTABLES_CONF"
      else
        rm -f "$NFTABLES_CONF"
      fi
      rm -f "$previous_table" "$previous_conf"
      return 1
    fi
  fi
  run_argv nft -f "$NFTABLES_CONF"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$had_conf" = '1' ]; then
      cp -p "$previous_conf" "$NFTABLES_CONF"
    else
      rm -f "$NFTABLES_CONF"
    fi
    nftables_restore_managed_table "$previous_table" "$had_table"
    rm -f "$previous_table" "$previous_conf"
    return "$rc"
  fi

  if ! nftables_verify_ssh_rule "$ssh_port"; then
    say '未能确认 SSH 端口放行规则，防火墙应用失败。' 'Could not verify the SSH allow rule, firewall apply failed.'
    if [ "$had_conf" = '1' ]; then
      cp -p "$previous_conf" "$NFTABLES_CONF"
    else
      rm -f "$NFTABLES_CONF"
    fi
    nftables_restore_managed_table "$previous_table" "$had_table"
    rm -f "$previous_table" "$previous_conf"
    return 1
  fi
  run_cmd 'systemctl enable nftables 2>/dev/null || true'

  state_set 'FIREWALL_MODE' 'nftables'
  state_set 'FIREWALL_SSH_PORT' "$ssh_port"
  nftables_warn_external_rules
  say "nftables 已应用，并已放行 SSH 端口 ${ssh_port}。" "nftables applied and SSH port ${ssh_port} is allowed."
  rm -f "$previous_table" "$previous_conf"
}

nftables_write_and_apply() {
  local ssh_port="$1"
  local source_ip="${2:-}"
  local allowed_tcp_ports="${3:-}"
  local allowed_udp_ports="${4:-}"
  local icmp_mode="${5:-off}"
  local forward_mode="${6:-docker}"
  local network_stack="${7:-unknown}"
  local tmp_file rc

  tmp_file="$(mktemp /tmp/linuxvm-init-nftables.XXXXXX)" || return 1
  nftables_render_ruleset "$tmp_file" "$ssh_port" "$source_ip" "$allowed_tcp_ports" "$allowed_udp_ports" "$icmp_mode" "$forward_mode" "$network_stack" || {
    rm -f "$tmp_file"
    return 1
  }
  nftables_apply_ruleset_file "$tmp_file" "$ssh_port"
  rc=$?
  rm -f "$tmp_file"
  return "$rc"
}

nftables_current_ssh_port() {
  local ssh_port
  ssh_port="$(state_get 'FIREWALL_SSH_PORT')"
  if ! is_valid_port "$ssh_port"; then
    ssh_port="$(effective_ssh_port)"
  fi
  if is_valid_port "$ssh_port"; then
    printf '%s\n' "$ssh_port"
  else
    printf '%s\n' ''
  fi
}

nftables_apply_current_state() {
  local ssh_port source_ip tcp_ports udp_ports icmp_mode forward_mode network_stack
  nftables_install || return 1
  network_stack="$(network_stack_refresh)"
  ssh_port="$(nftables_current_ssh_port)"
  if ! is_valid_port "$ssh_port"; then
    say '检测 SSH 端口失败，拒绝应用 nftables。' 'Failed to detect SSH port, refusing to apply nftables.'
    return 1
  fi
  source_ip="$(state_get 'FIREWALL_SSH_SOURCE_IP')"
  tcp_ports="$(nftables_allowed_ports)"
  udp_ports="$(nftables_allowed_udp_ports)"
  icmp_mode="$(nftables_icmp_mode)"
  forward_mode="$(nftables_forward_mode)"
  state_set 'FIREWALL_ICMP_MODE' "$icmp_mode"
  state_set 'FIREWALL_FORWARD_MODE' "$forward_mode"
  nftables_write_and_apply "$ssh_port" "$source_ip" "$tcp_ports" "$udp_ports" "$icmp_mode" "$forward_mode" "$network_stack"
}

nftables_allow_tcp_port() {
  local port="$1"
  if ! is_valid_port "$port"; then
    say '端口无效。' 'Invalid port.'
    return 1
  fi

  nftables_state_add_port "$port"
  nftables_apply_current_state
}

nftables_remove_tcp_port() {
  local port="$1"
  local ssh_port
  if ! is_valid_port "$port"; then
    say '端口无效。' 'Invalid port.'
    return 1
  fi

  ssh_port="$(nftables_current_ssh_port)"
  if [ "$port" = "$ssh_port" ]; then
    say '拒绝删除当前 SSH 端口放行规则。' 'Refusing to remove the current SSH allow rule.'
    return 1
  fi

  nftables_state_remove_port "$port"
  nftables_apply_current_state
}

nftables_allow_udp_port() {
  local port="$1"
  if ! is_valid_port "$port"; then
    say '端口无效。' 'Invalid port.'
    return 1
  fi

  nftables_state_add_udp_port "$port"
  nftables_apply_current_state
}

nftables_remove_udp_port() {
  local port="$1"
  if ! is_valid_port "$port"; then
    say '端口无效。' 'Invalid port.'
    return 1
  fi

  nftables_state_remove_udp_port "$port"
  nftables_apply_current_state
}

nftables_allow_icmp() {
  state_set 'FIREWALL_ICMP_MODE' 'essential'
  state_set 'FIREWALL_ALLOW_ICMP' '1'
  nftables_apply_current_state
}

nftables_remove_icmp() {
  state_set 'FIREWALL_ICMP_MODE' 'off'
  state_set 'FIREWALL_ALLOW_ICMP' '0'
  nftables_apply_current_state
}

nftables_allow_rule() {
  local protocol="$1"
  local value="${2:-}"
  protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
  case "$protocol" in
    tcp) nftables_allow_tcp_port "$value" ;;
    udp) nftables_allow_udp_port "$value" ;;
    icmp) nftables_allow_icmp ;;
    *)
      say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
      return 1
      ;;
  esac
}

nftables_remove_rule() {
  local protocol="$1"
  local value="${2:-}"
  protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
  case "$protocol" in
    tcp) nftables_remove_tcp_port "$value" ;;
    udp) nftables_remove_udp_port "$value" ;;
    icmp) nftables_remove_icmp ;;
    *)
      say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
      return 1
      ;;
  esac
}

firewall_can_modify_current_rules() {
  case "$(firewall_effective_mode)" in
    iptables)
      is_installed iptables || is_installed ip6tables
      ;;
    nftables)
      nftables_managed_active
      ;;
    *)
      return 1
      ;;
  esac
}

firewall_allow_rule() {
  local protocol="$1"
  local value="${2:-}"
  protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
  case "$protocol" in
    tcp|udp)
      if ! is_valid_port "$value"; then
        say '端口无效。' 'Invalid port.'
        return 1
      fi
      ;;
    icmp)
      value=''
      ;;
    *)
      say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
      return 1
      ;;
  esac

  case "$(firewall_effective_mode)" in
    iptables) iptables_mode_allow_rule "$protocol" "$value" ;;
    nftables) nftables_allow_rule "$protocol" "$value" ;;
    *) return 1 ;;
  esac
}

firewall_remove_rule() {
  local protocol="$1"
  local value="${2:-}"
  local ssh_port
  protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
  case "$protocol" in
    tcp|udp)
      if ! is_valid_port "$value"; then
        say '端口无效。' 'Invalid port.'
        return 1
      fi
      ;;
    icmp)
      value=''
      ;;
    *)
      say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
      return 1
      ;;
  esac

  if [ "$protocol" = 'tcp' ]; then
    ssh_port="$(nftables_current_ssh_port)"
    if [ "$value" = "$ssh_port" ]; then
      say '拒绝删除当前 SSH 端口放行规则。' 'Refusing to remove the current SSH allow rule.'
      return 1
    fi
  fi

  case "$(firewall_effective_mode)" in
    iptables) iptables_mode_remove_rule "$protocol" "$value" ;;
    nftables) nftables_remove_rule "$protocol" "$value" ;;
    *) return 1 ;;
  esac
}

nftables_allow_ssh_port() {
  local port="$1"
  if ! is_valid_port "$port"; then
    say 'SSH 端口无效。' 'Invalid SSH port.'
    return 1
  fi

  state_set 'FIREWALL_SSH_PORT' "$port"
  if nftables_managed_active; then
    nftables_apply_current_state
  elif nftables_legacy_firewall_detected; then
    say '检测到旧防火墙可能阻断新 SSH 端口。请先在防火墙面板切换到 nftables，再修改 SSH 端口。' 'A legacy firewall may block the new SSH port. Switch to nftables in the firewall panel before changing the SSH port.'
    return 1
  else
    say 'nftables 尚未由本脚本启用，已记录 SSH 端口，防火墙初始化时会放行。' 'nftables is not managed by this script yet; SSH port recorded and will be allowed during firewall setup.'
  fi
}

nftables_allow_ssh_from_ip() {
  local port="$1"
  local source_ip="$2"
  if ! is_valid_port "$port" || ! is_valid_ip "$source_ip"; then
    say 'SSH 来源 IP 或端口无效。' 'Invalid SSH source IP or port.'
    return 1
  fi

  state_set 'FIREWALL_SSH_PORT' "$port"
  state_set 'FIREWALL_SSH_SOURCE_IP' "$source_ip"
  if nftables_managed_active; then
    nftables_apply_current_state
  fi
}

apply_source_ip_whitelist_firewall() {
  local source_ip
  source_ip="$(detect_source_ip)"
  FIREWALL_SOURCE_IP=''
  if [ -z "$source_ip" ]; then
    say '未检测到来源 IP，跳过来源 IP 白名单保护。' 'Source IP not detected, skipping source whitelist protection.'
    return 0
  fi

  say "来源 IP 白名单保护：$source_ip" "Source IP whitelist protection: $source_ip"
  FIREWALL_SOURCE_IP="$source_ip"
}

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

nftables_setup() {
  local setup_tcp_ports
  local source_ip
  local iptables_frontend
  local network_stack
  say '风险提示：启用防火墙但未放行 SSH 端口会断开连接。' 'Warning: enabling firewall without SSH port will cut off access.'
  say '风险提示：nftables 将设置 INPUT/FORWARD 默认策略为 DROP。' 'Warning: nftables will set INPUT/FORWARD default policy to DROP.'

  nftables_install || return 1
  network_stack="$(network_stack_refresh)"
  say "检测到网络栈：${network_stack}（unknown 会按 dual 保守处理）" "Detected network stack: ${network_stack} (unknown is handled conservatively as dual)"
  iptables_frontend="$(nftables_refresh_iptables_frontend_state)"
  case "$iptables_frontend" in
    nft)
      say '检测到 iptables-nft 兼容层：它与 nftables 共用内核规则集，本脚本将继续使用 nftables 原生规则覆盖 IPv4/IPv6。' 'Detected iptables-nft compatibility layer; it shares the nftables kernel ruleset, and this script will keep using native nftables rules for IPv4/IPv6.'
      ;;
    legacy|mixed)
      say "检测到 iptables 前端状态：${iptables_frontend}。本脚本不会自动切换 alternatives；将以 nftables 原生规则为准。" "Detected iptables frontend: ${iptables_frontend}. This script will not change alternatives automatically; native nftables rules remain authoritative."
      ;;
  esac
  snapshot_create 'before-nftables-setup'

  if nftables_legacy_firewall_detected; then
    say '检测到旧防火墙配置、iptables 兼容层规则或其他 nftables 规则。切换前会先保存现有规则；iptables-nft 兼容层不会被禁用。' 'Detected legacy firewall config, iptables compatibility rules, or other nftables rules. Existing rules will be backed up first; iptables-nft compatibility will not be disabled.'
    if ! confirm '确认备份现有规则并应用 nftables？[y/N]' 'Back up existing rules and apply nftables? [y/N]'; then
      return 2
    fi
    nftables_backup_legacy_firewalls
    nftables_disable_legacy_firewalls
  fi

  detect_ssh_port_for_firewall || return 1
  say "防火墙将强制放行 SSH 端口 ${FIREWALL_SSH_PORT}" "Firewall will always allow SSH port ${FIREWALL_SSH_PORT}"
  apply_source_ip_whitelist_firewall
  source_ip="${FIREWALL_SOURCE_IP:-}"

  setup_tcp_ports="$(nftables_allowed_ports)"
  if confirm '放行 80 端口 (HTTP)？[y/N]' 'Allow port 80 (HTTP)? [y/N]'; then
    setup_tcp_ports="$(nftables_normalize_port_list "${setup_tcp_ports}${setup_tcp_ports:+,}80")"
  fi
  if confirm '放行 443 端口 (HTTPS)？[y/N]' 'Allow port 443 (HTTPS)? [y/N]'; then
    setup_tcp_ports="$(nftables_normalize_port_list "${setup_tcp_ports}${setup_tcp_ports:+,}443")"
  fi

  say "二次确认：即将放行 SSH 端口 ${FIREWALL_SSH_PORT}；ICMP=essential；FORWARD=docker；默认策略 INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT" "Final check: SSH port ${FIREWALL_SSH_PORT} will be allowed; ICMP=essential; FORWARD=docker; default policy to apply: INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT"
  if ! confirm '确认应用 nftables 防火墙？[y/N]' 'Confirm applying nftables firewall? [y/N]'; then
    return 2
  fi

  state_set 'FIREWALL_SSH_PORT' "$FIREWALL_SSH_PORT"
  state_set 'FIREWALL_SSH_SOURCE_IP' "$source_ip"
  state_set 'FIREWALL_ALLOWED_TCP_PORTS' "$setup_tcp_ports"
  state_set 'FIREWALL_ICMP_MODE' "$(nftables_setup_icmp_mode)"
  state_set 'FIREWALL_FORWARD_MODE' 'docker'
  nftables_apply_current_state || return 1
  run_cmd "nft list table ${NFTABLES_FAMILY} ${NFTABLES_TABLE}"
}

ufw_setup() {
  say 'ufw 后端已废弃，v1.0.7 起统一使用 nftables。' 'ufw backend is deprecated; v1.0.7 uses nftables only.'
  nftables_setup
}

iptables_setup() {
  say 'iptables 后端已废弃，v1.0.7 起统一使用 nftables。' 'iptables backend is deprecated; v1.0.7 uses nftables only.'
  nftables_setup
}

firewall_setup() {
  local requested_mode current_mode
  current_mode="$(state_get 'FIREWALL_MODE')"
  if [ -n "$current_mode" ]; then
    say "当前记录的防火墙模式：$current_mode" "Current recorded firewall mode: $current_mode"
  fi
  requested_mode="${NI_FIREWALL_MODE:-}"
  if [ -n "$requested_mode" ] && [ "$requested_mode" != 'nftables' ]; then
    say "NI_FIREWALL_MODE=${requested_mode} 已废弃，将统一使用 nftables。" "NI_FIREWALL_MODE=${requested_mode} is deprecated; nftables will be used."
  fi
  nftables_setup
}
