#!/usr/bin/env bash

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
