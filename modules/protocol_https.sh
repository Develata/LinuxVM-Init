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
  say 'iptables HTTPS 放行接口已兼容转发到 nftables。' 'iptables HTTPS allow interface is now forwarded to nftables.'
  nftables_allow_tcp_port "$PROTOCOL_HTTPS_PORT"
}
