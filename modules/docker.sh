#!/usr/bin/env bash

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

docker_install_compose() {
  if docker compose version >/dev/null 2>&1; then
    say '已检测到 Docker Compose（插件）。' 'Docker Compose plugin is already available.'
    return 0
  fi

  say '正在安装 Docker Compose 组件。' 'Installing Docker Compose component.'
  run_cmd 'apt update'
  run_cmd 'apt install -y docker-compose-plugin || apt install -y docker-compose'

  if docker compose version >/dev/null 2>&1; then
    say 'Docker Compose（插件）安装完成。' 'Docker Compose plugin installed.'
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    say 'Docker Compose（二进制）安装完成。' 'Docker Compose binary installed.'
    return 0
  fi

  say 'Docker Compose 安装失败，请检查网络或软件源。' 'Docker Compose install failed. Check network or apt sources.'
  return 1
}

docker_set_proxy() {
  local http_proxy https_proxy no_proxy
  say '用于 Docker 服务访问外网（拉取镜像等）。' 'Used by Docker service for outbound access (image pulls, etc.).'
  ask '输入 HTTP_PROXY（如 http://127.0.0.1:7890 ）：' 'Enter HTTP_PROXY (e.g. http://127.0.0.1:7890):' http_proxy
  ask '输入 HTTPS_PROXY（回车默认同 HTTP_PROXY）：' 'Enter HTTPS_PROXY (Enter to use HTTP_PROXY):' https_proxy
  ask '输入 NO_PROXY（可留空，如 localhost,127.0.0.1,.local）：' 'Enter NO_PROXY (optional, e.g. localhost,127.0.0.1,.local):' no_proxy

  if [ -z "$http_proxy" ]; then
    say 'HTTP_PROXY 不能为空。' 'HTTP_PROXY cannot be empty.'
    return 1
  fi
  [ -n "$https_proxy" ] || https_proxy="$http_proxy"

  backup_file '/etc/systemd/system/docker.service.d/http-proxy.conf'
  run_cmd 'mkdir -p /etc/systemd/system/docker.service.d'
  cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${http_proxy}"
Environment="HTTPS_PROXY=${https_proxy}"
Environment="NO_PROXY=${no_proxy}"
EOF

  run_cmd 'systemctl daemon-reload'
  run_cmd 'systemctl restart docker'
  say 'Docker 代理已设置完成。' 'Docker proxy configuration applied.'
}

docker_unset_proxy() {
  say '风险提示：清除代理后，Docker 可能无法访问外网。' 'Warning: after removing proxy, Docker may lose outbound access.'
  if ! confirm '确认清除 Docker 代理？[y/N]' 'Remove Docker proxy settings? [y/N]'; then
    return 2
  fi
  run_cmd 'rm -f /etc/systemd/system/docker.service.d/http-proxy.conf'
  run_cmd 'systemctl daemon-reload'
  run_cmd 'systemctl restart docker'
  say 'Docker 代理已清除。' 'Docker proxy configuration removed.'
}

docker_show_proxy() {
  run_cmd 'systemctl show --property=Environment docker'
  if [ -f /etc/systemd/system/docker.service.d/http-proxy.conf ]; then
    run_cmd 'sed -n "1,120p" /etc/systemd/system/docker.service.d/http-proxy.conf'
  fi
}

docker_install() {
  local mem_kb mem_mb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)"
  [ -n "$mem_kb" ] || mem_kb=0
  mem_mb=$((mem_kb / 1024))
  if [ "$mem_mb" -lt 1024 ] && [ "${DOCKER_ALLOW_LOW_MEM:-0}" != '1' ]; then
    say '检测到内存小于 1G，默认跳过 Docker 安装。' 'Detected memory below 1G, skipping Docker install by default.'
    return 2
  fi

  say '风险提示：Docker 会占用磁盘并启动后台服务。' 'Warning: Docker uses disk and starts background services.'
  if ! confirm '是否安装 Docker？[y/N]' 'Install Docker? [y/N]'; then
    return 2
  fi

  run_cmd 'curl -fsSL https://get.docker.com | sh'
  docker_install_compose

  if [ -n "${SUDO_USER:-}" ]; then
    say '风险提示：加入 docker 组相当于授予接近 root 的权限。' 'Warning: docker group is near-root access.'
    if confirm "是否将 ${SUDO_USER} 加入 docker 组？[y/N]" "Add ${SUDO_USER} to docker group? [y/N]"; then
      run_cmd "gpasswd -a ${SUDO_USER} docker"
    fi
  fi

  say '风险提示：设置日志限制会重启 Docker，容器会短暂中断。' 'Warning: log limits restart Docker and stop containers briefly.'
  if confirm '是否设置 Docker 日志大小限制？[y/N]' 'Configure Docker log limits? [y/N]'; then
    docker_write_log_limit '10m' '3'
  fi
}

docker_manage() {
  if ! is_installed docker; then
    say '当前未安装 Docker。' 'Docker is not installed.'
    if confirm '是否现在安装 Docker？[y/N]' 'Install Docker now? [y/N]'; then
      local mem_kb mem_mb
      mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)"
      [ -n "$mem_kb" ] || mem_kb=0
      mem_mb=$((mem_kb / 1024))
      if [ "$mem_mb" -lt 1024 ]; then
        say '检测到内存小于 1G。仅建议测试用途，可能影响系统稳定。' 'Detected memory below 1G. Test use only, may affect system stability.'
        if confirm '是否仍然强制安装 Docker？[y/N]' 'Force install Docker anyway? [y/N]'; then
          DOCKER_ALLOW_LOW_MEM='1'
          docker_install
          local rc=$?
          DOCKER_ALLOW_LOW_MEM='0'
          return "$rc"
        fi
        return 2
      fi
      docker_install
      return $?
    fi
    return 2
  fi

  while true; do
    say '==== Docker 管理 ====' '==== Docker Management ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 查看 Docker 状态'
      printf '%s\n' '2) 查看容器列表'
      printf '%s\n' '3) 重启 Docker 服务'
      printf '%s\n' '4) 修改日志限制'
      printf '%s\n' '5) 设置 Docker 代理'
      printf '%s\n' '6) 清除 Docker 代理'
      printf '%s\n' '7) 查看当前代理'
      printf '%s\n' '8) 安装/修复 Docker Compose'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) Show Docker service status'
      printf '%s\n' '2) Show containers'
      printf '%s\n' '3) Restart Docker service'
      printf '%s\n' '4) Update log limits'
      printf '%s\n' '5) Set Docker proxy'
      printf '%s\n' '6) Remove Docker proxy'
      printf '%s\n' '7) Show current proxy'
      printf '%s\n' '8) Install/repair Docker Compose'
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
      5) docker_set_proxy ;;
      6) docker_unset_proxy ;;
      7) docker_show_proxy ;;
      8) docker_install_compose ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}
