#!/usr/bin/env bash

docker_install() {
  say '风险提示：Docker 会占用磁盘并启动后台服务。' 'Warning: Docker uses disk and starts background services.'
  if ! confirm '是否安装 Docker？[y/N]' 'Install Docker? [y/N]'; then
    return 2
  fi
  run_cmd 'curl -fsSL https://get.docker.com | sh'

  if [ -n "${SUDO_USER:-}" ]; then
    say '风险提示：加入 docker 组相当于授予接近 root 的权限。' 'Warning: docker group is near-root access.'
    if confirm "是否将 ${SUDO_USER} 加入 docker 组？[y/N]" "Add ${SUDO_USER} to docker group? [y/N]"; then
      run_cmd "gpasswd -a ${SUDO_USER} docker"
    fi
  fi

  say '风险提示：设置日志限制会重启 Docker，容器会短暂中断。' 'Warning: log limits restart Docker and stop containers briefly.'
  if confirm '是否设置 Docker 日志大小限制？[y/N]' 'Configure Docker log limits? [y/N]'; then
    backup_file '/etc/docker/daemon.json'
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-file": "3",
    "max-size": "10m"
  }
}

docker_write_log_limit() {
  local max_size="$1"
  local max_file="$2"
  backup_file '/etc/docker/daemon.json'
  cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-file": "${max_file}",
    "max-size": "${max_size}"
  }
}
EOF
  run_cmd 'systemctl daemon-reload'
  run_cmd 'systemctl restart docker'
}

docker_manage() {
  if ! is_installed docker; then
    say '未安装 Docker，请先执行 Docker 安装。' 'Docker is not installed. Run Docker install first.'
    return 1
  fi

  while true; do
    say '==== Docker 管理 ====' '==== Docker Management ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 查看 Docker 状态'
      printf '%s\n' '2) 查看容器列表'
      printf '%s\n' '3) 重启 Docker 服务'
      printf '%s\n' '4) 修改日志限制'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) Show Docker service status'
      printf '%s\n' '2) Show containers'
      printf '%s\n' '3) Restart Docker service'
      printf '%s\n' '4) Update log limits'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) run_cmd 'systemctl status docker --no-pager -l' ;;
      2) run_cmd 'docker ps -a' ;;
      3) run_cmd 'systemctl restart docker' ;;
      4)
        ask '输入 max-size (如 10m):' 'Enter max-size (e.g. 10m):' max_size
        ask '输入 max-file (如 3):' 'Enter max-file (e.g. 3):' max_file
        if [[ "$max_size" =~ ^[0-9]+[kKmMgG]$ ]] && [[ "$max_file" =~ ^[0-9]+$ ]]; then
          docker_write_log_limit "$max_size" "$max_file"
        else
          say '日志参数格式无效。' 'Invalid log limit format.'
        fi
        ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
EOF
    run_cmd 'systemctl daemon-reload'
    run_cmd 'systemctl restart docker'
  fi
}
