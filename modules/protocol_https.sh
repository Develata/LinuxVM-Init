#!/usr/bin/env bash

PROTOCOL_HTTPS_PORT='443'

protocol_allow_https_nftables() {
  nftables_allow_tcp_port "$PROTOCOL_HTTPS_PORT"
}

protocol_allow_https_ufw() {
  say 'ufw HTTPS 放行接口已兼容转发到 nftables。' 'ufw HTTPS allow interface is now forwarded to nftables.'
  nftables_allow_tcp_port "$PROTOCOL_HTTPS_PORT"
}

protocol_allow_https_iptables() {
  say 'iptables 模式：将通过 iptables/ip6tables 放行 HTTPS。' 'iptables mode: allowing HTTPS through iptables/ip6tables.'
  iptables_mode_allow_rule tcp "$PROTOCOL_HTTPS_PORT"
}
