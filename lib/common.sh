#!/usr/bin/env bash

LANG_CHOICE='zh'
LOG_FILE='/var/log/vps-init.log'
DISTRO_ID=''
SSH_PORT=''
SUMMARY_FILE='/tmp/vps-init-summary.log'
NON_INTERACTIVE='0'
NI_AUTO_YES='0'
STATE_DIR='/etc/linuxvm-init'
STATE_FILE='/etc/linuxvm-init/state.env'
SNAPSHOT_DIR='/var/lib/linuxvm-init/snapshots'

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$COMMON_DIR/common_ui.sh"
source "$COMMON_DIR/common_exec.sh"
source "$COMMON_DIR/common_state.sh"
