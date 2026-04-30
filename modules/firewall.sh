#!/usr/bin/env bash

FIREWALL_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/firewall" && pwd)"

source "$FIREWALL_MODULE_DIR/common.sh"
source "$FIREWALL_MODULE_DIR/detect.sh"
source "$FIREWALL_MODULE_DIR/iptables_mode.sh"
source "$FIREWALL_MODULE_DIR/nftables_render.sh"
source "$FIREWALL_MODULE_DIR/nftables_apply.sh"
source "$FIREWALL_MODULE_DIR/nftables_rules.sh"
source "$FIREWALL_MODULE_DIR/legacy.sh"
source "$FIREWALL_MODULE_DIR/setup.sh"
