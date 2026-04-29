#!/usr/bin/env bash

PROTOCOL_HTTP_PORT='80'

protocol_allow_http_nftables() {
  nftables_allow_tcp_port "$PROTOCOL_HTTP_PORT"
}

protocol_allow_http_ufw() {
  say 'ufw HTTP 放行接口已兼容转发到 nftables。' 'ufw HTTP allow interface is now forwarded to nftables.'
  nftables_allow_tcp_port "$PROTOCOL_HTTP_PORT"
}

protocol_allow_http_iptables() {
  say 'iptables 模式：将通过 iptables/ip6tables 放行 HTTP。' 'iptables mode: allowing HTTP through iptables/ip6tables.'
  iptables_mode_allow_rule tcp "$PROTOCOL_HTTP_PORT"
}
