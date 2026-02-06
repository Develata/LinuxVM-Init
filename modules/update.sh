#!/usr/bin/env bash

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
    create_local_update_snapshot || return 1
    if ! run_cmd "git -C \"$BASE_DIR\" pull --ff-only"; then
      say 'git 更新失败，可能存在本地冲突。请先处理后重试。' 'Git update failed, likely due to local conflicts. Resolve and retry.'
      return 1
    fi
    run_cmd "chmod +x \"$BASE_DIR/vps-init.sh\" \"$BASE_DIR/selfcheck.sh\""
    say '脚本更新完成（git pull）。建议立即运行 ./selfcheck.sh' 'Update completed via git pull. Run ./selfcheck.sh next.'
    return 0
  fi

  say '当前目录不是 git 仓库或未安装 git。' 'Current directory is not a git repo or git is missing.'
  say '请使用以下方式更新：' 'Use the following update method:'
  printf '%s\n' 'git clone https://github.com/Develata/LinuxVM-Init.git'
  printf '%s\n' 'cd LinuxVM-Init && chmod +x vps-init.sh selfcheck.sh && ./selfcheck.sh'
  return 1
}
