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
  say 'iptables HTTP 放行接口已兼容转发到 nftables。' 'iptables HTTP allow interface is now forwarded to nftables.'
  nftables_allow_tcp_port "$PROTOCOL_HTTP_PORT"
}
