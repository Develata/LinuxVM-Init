#!/usr/bin/env bash

CURRENT_VERSION='unknown'
LATEST_VERSION='unknown'
VERSION_INFO_LOADED='0'

read_local_version() {
  if [ -f "$BASE_DIR/VERSION" ]; then
    tr -d ' \t\r\n' <"$BASE_DIR/VERSION"
  else
    printf '%s' ''
  fi
}

read_remote_version() {
  if [ -d "$BASE_DIR/.git" ] && is_installed git; then
    git -C "$BASE_DIR" show origin/master:VERSION 2>/dev/null | tr -d ' \t\r\n'
  else
    printf '%s' ''
  fi
}

refresh_version_info() {
  VERSION_INFO_LOADED='1'
  CURRENT_VERSION='unknown'
  LATEST_VERSION='unknown'

  local local_ver remote_ver
  local_ver="$(read_local_version)"

  if [ -d "$BASE_DIR/.git" ] && is_installed git; then
    git -C "$BASE_DIR" fetch -q origin >/dev/null 2>&1 || true
    remote_ver="$(read_remote_version)"

    if [ -n "$local_ver" ]; then
      CURRENT_VERSION="$local_ver"
    else
      CURRENT_VERSION="$(git -C "$BASE_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
    fi

    if [ -n "$remote_ver" ]; then
      LATEST_VERSION="$remote_ver"
    elif git -C "$BASE_DIR" rev-parse --short origin/master >/dev/null 2>&1; then
      LATEST_VERSION="$(git -C "$BASE_DIR" rev-parse --short origin/master 2>/dev/null || printf 'unknown')"
    fi
  elif [ -n "$local_ver" ]; then
    CURRENT_VERSION="$local_ver"
    LATEST_VERSION="$local_ver"
  fi
}

ensure_version_info() {
  if [ "${VERSION_INFO_LOADED:-0}" != '1' ]; then
    refresh_version_info
  fi
}

create_local_update_snapshot() {
  local backup_dir backup_file ts
  backup_dir="$BASE_DIR/.local-backups"
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_file="$backup_dir/linuxvm-init-preupdate-${ts}.tar.gz"

  run_cmd "mkdir -p \"$backup_dir\""
  if ! run_cmd "tar -czf \"$backup_file\" --exclude='.git' --exclude='.local-backups' -C \"$BASE_DIR\" ."; then
    say '本地快照创建失败，已停止更新。' 'Failed to create local snapshot. Update stopped.'
    return 1
  fi
  say "已创建本地快照：$backup_file" "Local snapshot created: $backup_file"
}

script_update() {
  say '项目作者 GitHub: Develata' 'Project owner GitHub: Develata'
  say '仓库地址: https://github.com/Develata/LinuxVM-Init' 'Repository: https://github.com/Develata/LinuxVM-Init'
  say '风险提示：更新会覆盖本地同名文件，请先备份你的自定义修改。' 'Warning: update may overwrite local files, backup local custom changes first.'

  if ! confirm '确认执行脚本更新？[y/N]' 'Proceed with script update? [y/N]'; then
    return 2
  fi

  if [ -d "$BASE_DIR/.git" ] && is_installed git; then
    run_cmd "git -C \"$BASE_DIR\" status --short"
    local dirty
    dirty="$(git -C "$BASE_DIR" status --porcelain 2>/dev/null || true)"
    if [ -n "$dirty" ]; then
      say '检测到本地改动。建议先自动 stash，再更新。' 'Local changes detected. Recommended: auto-stash before update.'
      if confirm '是否自动 stash 本地改动并继续更新？[y/N]' 'Auto-stash local changes and continue? [y/N]'; then
        run_cmd "git -C \"$BASE_DIR\" stash push -u -m \"linuxvm-init-auto-stash-$(date +%Y%m%d-%H%M%S)\""
      else
        say '已取消更新。你可以先手动提交或 stash 后再更新。' 'Update canceled. Commit or stash changes manually, then retry.'
        return 2
      fi
    fi

    create_local_update_snapshot || return 1
    if ! run_cmd "git -C \"$BASE_DIR\" pull --ff-only"; then
      say 'git 更新失败，可能存在本地冲突。请先处理后重试。' 'Git update failed, likely due to local conflicts. Resolve and retry.'
      say '可用命令：git status / git stash list / git stash pop' 'Useful commands: git status / git stash list / git stash pop'
      return 1
    fi
    run_cmd "chmod +x \"$BASE_DIR/vps-init.sh\" \"$BASE_DIR/selfcheck.sh\""
    refresh_version_info
    say '脚本更新完成（git pull）。建议立即运行 ./selfcheck.sh' 'Update completed via git pull. Run ./selfcheck.sh next.'
    return 0
  fi

  say '当前目录不是 git 仓库或未安装 git。' 'Current directory is not a git repo or git is missing.'
  say '请使用以下方式更新：' 'Use the following update method:'
  printf '%s\n' 'git clone https://github.com/Develata/LinuxVM-Init.git'
  printf '%s\n' 'cd LinuxVM-Init && chmod +x vps-init.sh selfcheck.sh && ./selfcheck.sh'
  return 1
}
