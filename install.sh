#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_CMD='/usr/local/bin/lvm'
SOURCE_SCRIPT="$BASE_DIR/vps-init.sh"
MARKER='# LinuxVM-Init managed wrapper'

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' 'Please run as root: sudo bash install.sh'
  exit 1
fi

if [ ! -f "$SOURCE_SCRIPT" ]; then
  printf '%s\n' "vps-init.sh not found at: $SOURCE_SCRIPT"
  exit 1
fi

if [ -L "$TARGET_CMD" ]; then
  existing_target="$(readlink -f "$TARGET_CMD" 2>/dev/null || true)"
  if [ -n "$existing_target" ] && [ "$existing_target" != "$SOURCE_SCRIPT" ]; then
    printf '%s\n' "Existing lvm symlink points to: $existing_target"
    printf '%s\n' 'It will be replaced with current repo path.'
  fi
  rm -f "$TARGET_CMD"
elif [ -f "$TARGET_CMD" ]; then
  if ! grep -qF "$MARKER" "$TARGET_CMD" 2>/dev/null; then
    printf '%s\n' "Existing lvm command is not managed by LinuxVM-Init: $TARGET_CMD"
    printf '%s\n' 'Refusing to overwrite it. Please move/remove it manually first.'
    exit 1
  fi
fi

chmod +x "$SOURCE_SCRIPT" "$BASE_DIR/selfcheck.sh"

cat > "$TARGET_CMD" <<EOF
#!/usr/bin/env bash
$MARKER
if [ "\${LVM_WRAPPER_SEEN:-0}" = '1' ]; then
  printf '%s\n' 'Detected wrapper recursion. Please restore ~/LinuxVM-Init/vps-init.sh from git.'
  exit 1
fi
export LVM_WRAPPER_SEEN='1'
exec bash "$SOURCE_SCRIPT" "\$@"
EOF
chmod +x "$TARGET_CMD"

printf '%s\n' "Installed command: lvm -> $SOURCE_SCRIPT"
printf '%s\n' 'Try: lvm'
