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
}

firewall_manage() {
  local current_mode op port protocol backup_dir
  current_mode="$(state_get 'FIREWALL_MODE')"
  if [ -n "$current_mode" ]; then
    say "当前记录模式：$current_mode" "Current recorded mode: $current_mode"
  fi

  while true; do
    say '==== nftables 防火墙管理 ====' '==== nftables Firewall Management ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '0) 首次安装/初始化防火墙'
      printf '%s\n' '1) 查看当前防火墙状态'
      printf '%s\n' '2) 查看脚本管理的 nftables 规则'
      printf '%s\n' '3) 添加放行规则（tcp/udp/icmp）'
      printf '%s\n' '4) 删除放行规则（tcp/udp/icmp）'
      printf '%s\n' '5) 重载当前 nftables 配置'
      printf '%s\n' '6) 查看最近旧防火墙备份目录'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '0) Initial firewall setup'
      printf '%s\n' '1) Show current firewall state'
      printf '%s\n' '2) Show managed nftables rules'
      printf '%s\n' '3) Add allow rule (tcp/udp/icmp)'
      printf '%s\n' '4) Remove allow rule (tcp/udp/icmp)'
      printf '%s\n' '5) Reload current nftables config'
      printf '%s\n' '6) Show latest legacy firewall backup directory'
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
        if ! is_installed nft; then
          say '未检测到 nftables。' 'nftables is not installed.'
        else
          run_cmd "nft list table ${NFTABLES_FAMILY} ${NFTABLES_TABLE}"
        fi
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
      b|B)
        return 0
        ;;
      *)
        say '输入无效。' 'Invalid input.'
        ;;
    esac
  done
}
