#!/usr/bin/env bash

PROTOCOL_HTTPS_PORT='443'

protocol_allow_https_ufw() {
  run_cmd "ufw allow $PROTOCOL_HTTPS_PORT"
}

protocol_allow_https_iptables() {
  iptables_allow_port "$PROTOCOL_HTTPS_PORT"
}
