#!/usr/bin/env bash
set -u

TARGET_CMD='/usr/local/bin/lvm'

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' 'Please run as root: sudo bash uninstall.sh'
  exit 1
fi

if [ -L "$TARGET_CMD" ]; then
  rm -f "$TARGET_CMD"
  printf '%s\n' 'Removed command: lvm'
elif [ -f "$TARGET_CMD" ]; then
  printf '%s\n' "Refusing to remove non-symlink file: $TARGET_CMD"
  printf '%s\n' 'Please check it manually to avoid deleting unrelated commands.'
  exit 1
else
  printf '%s\n' 'No lvm command found in /usr/local/bin'
fi
