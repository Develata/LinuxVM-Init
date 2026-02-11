#!/usr/bin/env bash
set -u

TARGET_CMD='/usr/local/bin/lvm'
MARKER='# LinuxVM-Init managed wrapper'

is_linuxvm_repo_script() {
  local target="$1"
  local target_dir
  [ -f "$target" ] || return 1
  target_dir="$(cd "$(dirname "$target")" && pwd)"
  [ -f "$target_dir/vps-init.sh" ] || return 1
  [ -d "$target_dir/lib" ] || return 1
  [ -d "$target_dir/modules" ] || return 1
}

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' 'Please run as root: sudo bash uninstall.sh'
  exit 1
fi

if [ -L "$TARGET_CMD" ]; then
  existing_target="$(readlink -f "$TARGET_CMD" 2>/dev/null || true)"
  if is_linuxvm_repo_script "$existing_target"; then
    rm -f "$TARGET_CMD"
    printf '%s\n' "Removed command: lvm (symlink to $existing_target)"
  else
    printf '%s\n' "Refusing to remove unmanaged symlink: $TARGET_CMD -> ${existing_target:-unknown}"
    printf '%s\n' 'Please check it manually to avoid deleting unrelated commands.'
    exit 1
  fi
elif [ -f "$TARGET_CMD" ]; then
  if grep -qF "$MARKER" "$TARGET_CMD" 2>/dev/null; then
    rm -f "$TARGET_CMD"
    printf '%s\n' 'Removed command: lvm'
  else
    printf '%s\n' "Refusing to remove non-managed file: $TARGET_CMD"
    printf '%s\n' 'Please check it manually to avoid deleting unrelated commands.'
    exit 1
  fi
else
  printf '%s\n' 'No lvm command found in /usr/local/bin'
fi
