#!/usr/bin/env bash

PROTOCOL_HTTP_PORT='80'

protocol_allow_http_ufw() {
  run_cmd "ufw allow $PROTOCOL_HTTP_PORT"
}

protocol_allow_http_iptables() {
  iptables_allow_port "$PROTOCOL_HTTP_PORT"
}
