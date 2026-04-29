#!/usr/bin/env bash

nftables_show_state() {
  local ssh_port source_ip tcp_ports udp_ports icmp_mode forward_mode backup_dir
  ssh_port="$(nftables_current_ssh_port)"
  source_ip="$(state_get 'FIREWALL_SSH_SOURCE_IP')"
  tcp_ports="$(nftables_allowed_ports)"
  udp_ports="$(nftables_allowed_udp_ports)"
  icmp_mode="$(nftables_icmp_mode)"
  forward_mode="$(nftables_forward_mode)"
  backup_dir="$(state_get 'LAST_LEGACY_FIREWALL_BACKUP')"

  say '==== 当前防火墙状态 ====' '==== Current Firewall State ===='
  printf 'FIREWALL_MODE=%s\n' "$(state_get 'FIREWALL_MODE')"
  printf 'FIREWALL_SSH_PORT=%s\n' "${ssh_port:-unknown}"
  printf 'FIREWALL_SSH_SOURCE_IP=%s\n' "${source_ip:-any}"
  printf 'FIREWALL_ALLOWED_TCP_PORTS=%s\n' "${tcp_ports:-none}"
  printf 'FIREWALL_ALLOWED_UDP_PORTS=%s\n' "${udp_ports:-none}"
  printf 'FIREWALL_ICMP_MODE=%s\n' "$icmp_mode"
  printf 'FIREWALL_FORWARD_MODE=%s\n' "$forward_mode"
  printf 'LAST_LEGACY_FIREWALL_BACKUP=%s\n' "${backup_dir:-none}"
  network_stack_show_state
  nftables_show_compat_state
}

firewall_show_iptables_rules() {
  if is_installed iptables; then
    say '==== IPv4 iptables filter ====' '==== IPv4 iptables filter ===='
    run_argv iptables -nvL --line-numbers
    say '==== IPv4 iptables nat ====' '==== IPv4 iptables nat ===='
    run_argv iptables -t nat -nvL --line-numbers
  else
    say '未检测到 iptables。' 'iptables is not installed.'
  fi

  if is_installed ip6tables; then
    say '==== IPv6 ip6tables filter ====' '==== IPv6 ip6tables filter ===='
    run_argv ip6tables -nvL --line-numbers
    say '==== IPv6 ip6tables nat ====' '==== IPv6 ip6tables nat ===='
    run_argv ip6tables -t nat -nvL --line-numbers
  else
    say '未检测到 ip6tables。' 'ip6tables is not installed.'
  fi
}

firewall_show_nftables_rules() {
  if ! is_installed nft; then
    say '未检测到 nftables。' 'nftables is not installed.'
  elif nftables_managed_active; then
    run_cmd "nft list table ${NFTABLES_FAMILY} ${NFTABLES_TABLE}"
  else
    say '未检测到脚本管理的 nftables 表。可用完整 ruleset 查看现有防火墙。' 'Managed nftables table was not found. Use full ruleset view to inspect the current firewall.'
  fi
}

firewall_show_current_rules() {
  local mode
  mode="$(state_get 'FIREWALL_MODE')"
  case "$mode" in
    iptables) firewall_show_iptables_rules ;;
    *) firewall_show_nftables_rules ;;
  esac
}

firewall_show_full_ruleset() {
  if ! is_installed nft; then
    say '未检测到 nftables。' 'nftables is not installed.'
  else
    run_cmd 'nft list ruleset'
  fi
}

firewall_manage() {
  local current_mode op port protocol backup_dir refreshed_stack
  current_mode="$(state_get 'FIREWALL_MODE')"
  if [ -n "$current_mode" ]; then
    say "当前记录模式：$current_mode" "Current recorded mode: $current_mode"
  fi

  while true; do
    say '==== nftables 防火墙管理 ====' '==== nftables Firewall Management ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '0) 首次安装/初始化防火墙'
      printf '%s\n' '1) 查看当前防火墙状态'
      printf '%s\n' '2) 按当前模式查看规则'
      printf '%s\n' '3) 添加放行规则（tcp/udp/icmp）'
      printf '%s\n' '4) 删除放行规则（tcp/udp/icmp）'
      printf '%s\n' '5) 重载当前 nftables 配置'
      printf '%s\n' '6) 查看最近旧防火墙备份目录'
      printf '%s\n' '7) 刷新网络栈检测'
      printf '%s\n' '8) 查看完整 nftables ruleset'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '0) Initial firewall setup'
      printf '%s\n' '1) Show current firewall state'
      printf '%s\n' '2) Show rules for current mode'
      printf '%s\n' '3) Add allow rule (tcp/udp/icmp)'
      printf '%s\n' '4) Remove allow rule (tcp/udp/icmp)'
      printf '%s\n' '5) Reload current nftables config'
      printf '%s\n' '6) Show latest legacy firewall backup directory'
      printf '%s\n' '7) Refresh network stack detection'
      printf '%s\n' '8) Show full nftables ruleset'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      0)
        firewall_setup
        ;;
      1)
        nftables_show_state
        ;;
      2)
        firewall_show_current_rules
        ;;
      3)
        if ! nftables_managed_active; then
          say 'nftables 尚未初始化，请先执行 0。' 'nftables is not initialized yet; run option 0 first.'
          continue
        fi
        ask '输入协议 tcp/udp/icmp：' 'Enter protocol tcp/udp/icmp:' protocol
        protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
        port=''
        case "$protocol" in
          tcp|udp)
            ask '输入要放行的端口：' 'Enter port to allow:' port
            ;;
          icmp)
            ;;
          *)
            say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
            continue
            ;;
        esac
        nftables_allow_rule "$protocol" "$port"
        ;;
      4)
        if ! nftables_managed_active; then
          say 'nftables 尚未初始化，请先执行 0。' 'nftables is not initialized yet; run option 0 first.'
          continue
        fi
        ask '输入协议 tcp/udp/icmp：' 'Enter protocol tcp/udp/icmp:' protocol
        protocol="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
        port=''
        case "$protocol" in
          tcp|udp)
            ask '输入要删除放行的端口：' 'Enter allowed port to remove:' port
            ;;
          icmp)
            ;;
          *)
            say '协议无效，请输入 tcp、udp 或 icmp。' 'Invalid protocol, use tcp, udp, or icmp.'
            continue
            ;;
        esac
        nftables_remove_rule "$protocol" "$port"
        ;;
      5)
        if ! nftables_managed_active; then
          say 'nftables 尚未初始化，请先执行 0。' 'nftables is not initialized yet; run option 0 first.'
          continue
        fi
        nftables_apply_current_state
        ;;
      6)
        backup_dir="$(state_get 'LAST_LEGACY_FIREWALL_BACKUP')"
        if [ -n "$backup_dir" ]; then
          say "最近旧防火墙备份目录：$backup_dir" "Latest legacy firewall backup directory: $backup_dir"
          run_argv ls -la "$backup_dir"
        else
          say '尚无旧防火墙备份记录。' 'No legacy firewall backup has been recorded.'
        fi
        ;;
      7)
        refreshed_stack="$(network_stack_refresh)"
        say "已刷新网络栈：${refreshed_stack}" "Network stack refreshed: ${refreshed_stack}"
        ;;
      8)
        firewall_show_full_ruleset
        ;;
      b|B)
        return 0
        ;;
      *)
        say '输入无效。' 'Invalid input.'
        ;;
    esac
  done
}
