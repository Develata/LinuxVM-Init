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
EOF
    run_cmd 'systemctl daemon-reload'
    run_cmd 'systemctl restart docker'
  fi
}
