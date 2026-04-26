#!/usr/bin/env bash

PROTOCOL_HTTPS_PORT='443'

protocol_allow_https_ufw() {
  run_argv ufw allow "${PROTOCOL_HTTPS_PORT}/tcp"
}

protocol_allow_https_iptables() {
  iptables_allow_port "$PROTOCOL_HTTPS_PORT"
}
