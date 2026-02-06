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

iptables_has_rule() {
  local port="$1"
  iptables -C INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1
}

iptables_ensure_base_rules() {
  while iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT >/dev/null 2>&1; do
    run_cmd 'iptables -D INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT'
  done
  run_cmd 'iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT'

  while iptables -C INPUT -i lo -j ACCEPT >/dev/null 2>&1; do
    run_cmd 'iptables -D INPUT -i lo -j ACCEPT'
  done
  run_cmd 'iptables -A INPUT -i lo -j ACCEPT'
}

iptables_allow_port() {
  local port="$1"
  while iptables_has_rule "$port"; do
    run_cmd "iptables -D INPUT -p tcp --dport $port -j ACCEPT"
  done
  run_cmd "iptables -A INPUT -p tcp --dport $port -j ACCEPT"
}

iptables_setup() {
  say '风险提示：iptables 配置错误会导致 SSH 断连。' 'Warning: wrong iptables rules can lock you out of SSH.'
  say '风险提示：该模式会设置 INPUT/FORWARD 默认策略为 DROP。' 'Warning: this mode sets INPUT/FORWARD default policy to DROP.'
  if ! confirm '继续使用 iptables 防火墙？[y/N]' 'Continue with iptables firewall? [y/N]'; then
    return 2
  fi

  run_cmd 'DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent'
  run_cmd 'mkdir -p /etc/iptables'
  if [ ! -f /etc/iptables/rules.v4.bak ]; then
    run_cmd 'iptables-save > /etc/iptables/rules.v4.bak'
  fi

  iptables_ensure_base_rules

  local ssh_port
  ssh_port="$(effective_ssh_port)"
  if confirm "放行 SSH 端口 ${ssh_port}？[y/N]" "Allow SSH port ${ssh_port}? [y/N]"; then
    iptables_allow_port "$ssh_port"
  fi
  if confirm '放行 80 端口 (HTTP)？[y/N]' 'Allow port 80 (HTTP)? [y/N]'; then
    iptables_allow_port '80'
  fi
  if confirm '放行 443 端口 (HTTPS)？[y/N]' 'Allow port 443 (HTTPS)? [y/N]'; then
    iptables_allow_port '443'
  fi

  run_cmd 'iptables -P INPUT DROP'
  run_cmd 'iptables -P FORWARD DROP'
  run_cmd 'iptables -P OUTPUT ACCEPT'
  run_cmd 'iptables-save > /etc/iptables/rules.v4'
  run_cmd 'netfilter-persistent save'
  run_cmd 'netfilter-persistent reload'
  run_cmd 'iptables -L -n --line-numbers'
}

firewall_setup() {
  say '请选择防火墙方案：1) ufw 2) iptables' 'Choose firewall backend: 1) ufw 2) iptables'
  printf '%s ' '> '
  read -r fw_mode
  case "$fw_mode" in
    1|'') ufw_setup ;;
    2) iptables_setup ;;
    *)
      say '输入无效，请输入 1 或 2。' 'Invalid input, please enter 1 or 2.'
      return 1
      ;;
  esac
}
