#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_CMD='/usr/local/bin/lvm'
SOURCE_SCRIPT="$BASE_DIR/vps-init.sh"

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' 'Please run as root: sudo bash install.sh'
  exit 1
fi

if [ ! -f "$SOURCE_SCRIPT" ]; then
  printf '%s\n' "vps-init.sh not found at: $SOURCE_SCRIPT"
  exit 1
fi

if [ -e "$TARGET_CMD" ] && [ ! -L "$TARGET_CMD" ]; then
  printf '%s\n' "Existing non-symlink command detected: $TARGET_CMD"
  printf '%s\n' 'Refusing to overwrite it. Please move/remove it manually first.'
  exit 1
fi

if [ -L "$TARGET_CMD" ]; then
  existing_target="$(readlink -f "$TARGET_CMD" 2>/dev/null || true)"
  if [ -n "$existing_target" ] && [ "$existing_target" != "$SOURCE_SCRIPT" ]; then
    printf '%s\n' "Existing lvm symlink points to: $existing_target"
    printf '%s\n' 'It will be replaced with current repo path.'
  fi
fi

chmod +x "$SOURCE_SCRIPT" "$BASE_DIR/selfcheck.sh"
ln -sf "$SOURCE_SCRIPT" "$TARGET_CMD"

printf '%s\n' "Installed command: lvm -> $SOURCE_SCRIPT"
printf '%s\n' 'Try: lvm'
