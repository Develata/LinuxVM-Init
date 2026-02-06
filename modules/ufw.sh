#!/usr/bin/env bash

detect_ssh_port_for_firewall() {
  local ssh_port
  ssh_port="$(effective_ssh_port)"
  if ! is_valid_port "$ssh_port"; then
    say '检测 SSH 端口失败，已取消防火墙设置。' 'Failed to detect SSH port, firewall setup canceled.'
    return 1
  fi

  if is_port_in_use "$ssh_port"; then
    say "已检测到 SSH 端口: ${ssh_port}" "Detected SSH port: ${ssh_port}"
  else
    say "检测到 SSH 端口: ${ssh_port}（当前监听未确认，请谨慎）" "Detected SSH port: ${ssh_port} (listener not confirmed, proceed carefully)"
  fi
  FIREWALL_SSH_PORT="$ssh_port"
}

apply_source_ip_whitelist_firewall() {
  local source_ip
  source_ip="$(detect_source_ip)"
  if [ -z "$source_ip" ]; then
    say '未检测到来源 IP，跳过来源 IP 白名单保护。' 'Source IP not detected, skipping source whitelist protection.'
    return
  fi

  say "来源 IP 白名单保护：$source_ip" "Source IP whitelist protection: $source_ip"
  if state_get 'FIREWALL_MODE' | grep -q '^ufw$'; then
    run_cmd "ufw allow from $source_ip to any port $FIREWALL_SSH_PORT proto tcp"
  else
    if ! iptables -C INPUT -p tcp -s "$source_ip" --dport "$FIREWALL_SSH_PORT" -j ACCEPT >/dev/null 2>&1; then
      run_cmd "iptables -I INPUT 1 -p tcp -s $source_ip --dport $FIREWALL_SSH_PORT -j ACCEPT"
    fi
  fi
}

ufw_default_policy() {
  local defaults
  defaults="$(ufw status verbose 2>/dev/null | awk -F': ' '/^Default:/{print $2; exit}')"
  if [ -z "$defaults" ]; then
    defaults='deny (incoming), allow (outgoing), disabled (routed)'
  fi
  printf '%s\n' "$defaults"
}

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

  snapshot_create 'before-ufw-setup'
  detect_ssh_port_for_firewall || return 1
  say "防火墙将强制放行 SSH 端口 ${FIREWALL_SSH_PORT}" "Firewall will always allow SSH port ${FIREWALL_SSH_PORT}"
  run_cmd "ufw allow $FIREWALL_SSH_PORT"
  state_set 'FIREWALL_MODE' 'ufw'
  apply_source_ip_whitelist_firewall

  if confirm '放行 80 端口 (HTTP)？[y/N]' 'Allow port 80 (HTTP)? [y/N]'; then
    run_cmd 'ufw allow 80'
  fi
  if confirm '放行 443 端口 (HTTPS)？[y/N]' 'Allow port 443 (HTTPS)? [y/N]'; then
    run_cmd 'ufw allow 443'
  fi

  local ufw_defaults
  ufw_defaults="$(ufw_default_policy)"
  say "二次确认：即将放行 SSH 端口 ${FIREWALL_SSH_PORT}；即将启用的 UFW 默认策略：${ufw_defaults}" "Final check: SSH port ${FIREWALL_SSH_PORT} will be allowed; UFW default policy to apply: ${ufw_defaults}"
  if confirm '确认启用 ufw 防火墙？[y/N]' 'Confirm enabling ufw firewall? [y/N]'; then
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
  snapshot_create 'before-iptables-setup'
  if [ ! -f /etc/iptables/rules.v4.bak ]; then
    run_cmd 'iptables-save > /etc/iptables/rules.v4.bak'
  fi

  iptables_ensure_base_rules

  detect_ssh_port_for_firewall || return 1
  say "防火墙将强制放行 SSH 端口 ${FIREWALL_SSH_PORT}" "Firewall will always allow SSH port ${FIREWALL_SSH_PORT}"
  state_set 'FIREWALL_MODE' 'iptables'
  apply_source_ip_whitelist_firewall
  iptables_allow_port "$FIREWALL_SSH_PORT"
  if confirm '放行 80 端口 (HTTP)？[y/N]' 'Allow port 80 (HTTP)? [y/N]'; then
    iptables_allow_port '80'
  fi
  if confirm '放行 443 端口 (HTTPS)？[y/N]' 'Allow port 443 (HTTPS)? [y/N]'; then
    iptables_allow_port '443'
  fi

  say "二次确认：即将放行 SSH 端口 ${FIREWALL_SSH_PORT}；即将启用默认策略 INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT" "Final check: SSH port ${FIREWALL_SSH_PORT} will be allowed; default policy to apply: INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT"
  if ! confirm '确认应用上述 iptables 默认策略？[y/N]' 'Confirm applying these iptables default policies? [y/N]'; then
    return 2
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
  local current_mode
  local fw_mode
  current_mode="$(state_get 'FIREWALL_MODE')"
  if [ -n "$current_mode" ]; then
    say "当前记录的防火墙模式：$current_mode" "Current recorded firewall mode: $current_mode"
  fi
  say '请选择防火墙方案：1) ufw 2) iptables' 'Choose firewall backend: 1) ufw 2) iptables'
  if [ "$NON_INTERACTIVE" = '1' ]; then
    fw_mode="${NI_FIREWALL_MODE:-}"
    if [ -z "$fw_mode" ] && [ -n "$current_mode" ]; then
      fw_mode="$([ "$current_mode" = 'iptables' ] && printf '2' || printf '1')"
    fi
    if [ -z "$fw_mode" ]; then
      fw_mode='1'
    fi
  else
    printf '%s ' '> '
    read -r fw_mode
  fi
  case "$fw_mode" in
    1|ufw|'') ufw_setup ;;
    2|iptables) iptables_setup ;;
    *)
      say '输入无效，请输入 1 或 2。' 'Invalid input, please enter 1 or 2.'
      return 1
      ;;
  esac
}
