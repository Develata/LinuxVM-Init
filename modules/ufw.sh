#!/usr/bin/env bash

ufw_setup() {
  say '风险提示：启用防火墙但未放行 SSH 端口会断开连接。' 'Warning: enabling firewall without SSH port will cut off access.'
  say '风险提示：开放不必要端口会增加被攻击面。' 'Warning: opening unused ports increases exposure.'
  if ! is_installed ufw; then
    if confirm '未安装 ufw，是否安装？[y/N]' 'ufw not installed, install now? [y/N]'; then
      run_cmd 'apt install -y ufw'
    else
      return 2
    fi
  fi

  local ssh_rule_port
  ssh_rule_port="$(effective_ssh_port)"
  if confirm "放行 SSH 端口 ${ssh_rule_port}？[y/N]" "Allow SSH port ${ssh_rule_port}? [y/N]"; then
    run_cmd "ufw allow $ssh_rule_port"
  fi

  if confirm '放行 80 端口 (HTTP)？[y/N]' 'Allow port 80 (HTTP)? [y/N]'; then
    run_cmd 'ufw allow 80'
  fi
  if confirm '放行 443 端口 (HTTPS)？[y/N]' 'Allow port 443 (HTTPS)? [y/N]'; then
    run_cmd 'ufw allow 443'
  fi

  if confirm '启用 ufw 防火墙？[y/N]' 'Enable ufw firewall? [y/N]'; then
    run_cmd 'ufw --force enable'
  else
    return 2
  fi
  run_cmd 'ufw status'
}
