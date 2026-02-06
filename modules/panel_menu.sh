#!/usr/bin/env bash
show_main_dashboard() {
  local fw_mode last_snapshot ssh_port f2b_state
  ensure_version_info
  fw_mode="$(state_get 'FIREWALL_MODE')"
  last_snapshot="$(state_get 'LAST_SNAPSHOT')"
  ssh_port="$(current_ssh_port)"
  f2b_state="$(systemctl is-active fail2ban 2>/dev/null || printf 'unknown')"
  [ -z "$fw_mode" ] && fw_mode='unknown'
  [ -z "$last_snapshot" ] && last_snapshot='none'
  say '维护者: Develata | 仓库: https://github.com/Develata/LinuxVM-Init' 'Maintainer: Develata | Repo: https://github.com/Develata/LinuxVM-Init'
  say "版本: 当前=${CURRENT_VERSION} 最新=${LATEST_VERSION}" "Version: current=${CURRENT_VERSION} latest=${LATEST_VERSION}"
  say "状态: 系统=$DISTRO_ID SSH=$ssh_port 防火墙=$fw_mode fail2ban=$f2b_state 快照=$last_snapshot" "Status: distro=$DISTRO_ID SSH=$ssh_port firewall=$fw_mode fail2ban=$f2b_state snapshot=$last_snapshot"
}

init_flow() {
  say 'Init 一键顺序配置将按安全顺序执行基础步骤。' 'Init one-click flow runs baseline steps in safe order.'
  say '风险提示：请保持当前 SSH 会话，不要中断。' 'Warning: keep your current SSH session open.'
  confirm '继续执行？[y/N]' 'Proceed? [y/N]' || return 2

  say '步骤1/8：系统更新。说明：会更新软件包索引并安装可升级项，可能耗时。' 'Step 1/8: system update. Note: updates package index and installs available upgrades.'
  run_step 'system_update' system_update

  say '步骤2/8：常用工具。说明：vim 和 command-not-found 默认跳过，直接回车即可。' 'Step 2/8: tools. Note: vim and command-not-found are skipped by default, press Enter to skip.'
  run_step 'tools_install' tools_install

  say '步骤3/8：创建普通用户。说明：先输入用户名，再设置密码，资料项可连续回车，最后输入 Y 确认。' 'Step 3/8: create user. Note: enter username, set password, press Enter for profile fields, then type Y.'
  run_step 'user_add' user_add

  say '步骤4/8：SSH 与防火墙。说明：若启用 SSH 设置，只需选一次端口，然后配置防火墙并应用 SSH。' 'Step 4/8: SSH and firewall. Note: if enabled, choose SSH port once, then configure firewall and apply SSH.'
  if confirm '是否执行 SSH 安全设置（默认跳过）？[y/N]' 'Apply SSH hardening (default skip)? [y/N]'; then
    choose_ssh_port
    case "$?" in
      0)
        record_step 'choose_ssh_port' 'success'
        run_step 'firewall_setup' firewall_setup
        run_step 'ssh_apply_selected_port' ssh_apply_selected_port
        ;;
      2)
        record_step 'choose_ssh_port' 'skipped'
        record_step 'firewall_setup' 'skipped'
        record_step 'ssh_apply_selected_port' 'skipped'
        ;;
      *)
        record_step 'choose_ssh_port' 'failed'
        record_step 'firewall_setup' 'skipped'
        record_step 'ssh_apply_selected_port' 'skipped'
        ;;
    esac
  else
    record_step 'choose_ssh_port' 'skipped'
    run_step 'firewall_setup' firewall_setup
    record_step 'ssh_apply_selected_port' 'skipped'
  fi

  say '步骤5/8：fail2ban。说明：默认参数已较保守，失败登录过多会自动封禁。' 'Step 5/8: fail2ban. Note: defaults are conservative and block repeated failed logins.'
  run_step 'fail2ban_setup' fail2ban_setup

  say '步骤6/8：自动安全更新。说明：启用后系统会自动执行安全更新。' 'Step 6/8: unattended upgrades. Note: enables automatic security updates.'
  run_step 'unattended_enable' unattended_enable

  say '步骤7/8：Swap（可选）。说明：不需要可直接回车跳过。' 'Step 7/8: swap (optional). Note: press Enter to skip if not needed.'
  if confirm '是否执行 Swap 配置？[y/N]' 'Configure swap now? [y/N]'; then
    run_step 'swap_setup' swap_setup
  else
    record_step 'swap_setup' 'skipped'
  fi

  say '步骤8/8：1panel（可选）。说明：不需要可直接回车跳过。' 'Step 8/8: 1panel (optional). Note: press Enter to skip if not needed.'
  if confirm '是否安装 1panel？[y/N]' 'Install 1panel? [y/N]'; then
    run_step 'onepanel_install' onepanel_install
  else
    record_step 'onepanel_install' 'skipped'
  fi
}

system_menu() {
  while true; do
    say '==== 系统维护 ====' '==== System Maintenance ===='
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '1) 系统更新'
      printf '%s\n' '2) 常用工具安装'
      printf '%s\n' '3) 添加普通用户 + sudo'
      printf '%s\n' '4) 安全更新 (unattended-upgrades)'
      printf '%s\n' '5) logrotate 配置'
      printf '%s\n' '6) 1panel 安装'
      printf '%s\n' 'b) 返回'
    else
      printf '%s\n' '1) System update'
      printf '%s\n' '2) Install tools'
      printf '%s\n' '3) Add user + sudo'
      printf '%s\n' '4) Enable unattended-upgrades'
      printf '%s\n' '5) logrotate setup'
      printf '%s\n' '6) Install 1panel'
      printf '%s\n' 'b) Back'
    fi
    printf '%s ' '> '
    read -r op
    case "$op" in
      1) run_step 'system_update' system_update ;;
      2) run_step 'tools_install' tools_install ;;
      3) run_step 'user_add' user_add ;;
      4) run_step 'unattended_enable' unattended_enable ;;
      5) run_step 'logrotate_setup' logrotate_setup ;;
      6) run_step 'onepanel_install' onepanel_install ;;
      b|B) return 0 ;;
      *) say '输入无效。' 'Invalid input.' ;;
    esac
  done
}

main_menu() {
  while true; do
    say '==== LinuxVM-Init 菜单 ====' '==== LinuxVM-Init Menu ===='
    show_main_dashboard
    say '提示：输入编号执行；输入 q 退出。' 'Tip: enter a number to run; enter q to quit.'
    if [ "$LANG_CHOICE" = 'zh' ]; then
      printf '%s\n' '0) Init 一键顺序配置（推荐）'
      printf '%s\n' '1) SSH 管理面板'
      printf '%s\n' '2) Docker 管理面板'
      printf '%s\n' '3) 防火墙管理面板'
      printf '%s\n' '4) fail2ban 管理面板'
      printf '%s\n' '5) 系统维护'
      printf '%s\n' '6) Swap 管理'
      printf '%s\n' '7) 快照与回滚'
      printf '%s\n' '8) 巡检与每日简报'
      printf '%s\n' '9) 脚本更新'
      printf '%s\n' '10) 清空已记住的语言/系统'
      printf '%s\n' '99) 新手一键修复（应急）'
      printf '%s\n' 'q) 退出'
    else
      printf '%s\n' '0) Init one-click flow (recommended)'
      printf '%s\n' '1) SSH panel'
      printf '%s\n' '2) Docker panel'
      printf '%s\n' '3) Firewall panel'
      printf '%s\n' '4) fail2ban panel'
      printf '%s\n' '5) System maintenance'
      printf '%s\n' '6) Swap management'
      printf '%s\n' '7) Snapshot and restore'
      printf '%s\n' '8) Inspection and daily report'
      printf '%s\n' '9) Script update'
      printf '%s\n' '10) Reset saved language/distro'
      printf '%s\n' '99) Novice one-click safe repair (emergency)'
      printf '%s\n' 'q) Quit'
    fi
    printf '%s ' '> '
    read -r choice
    case "$choice" in
      0) run_step 'init_flow' init_flow ;;
      1) run_step 'ssh_manage' ssh_manage ;;
      2) run_step 'docker_manage' docker_manage ;;
      3) run_step 'firewall_manage' firewall_manage ;;
      4) run_step 'fail2ban_manage' fail2ban_manage ;;
      5) run_step 'system_menu' system_menu ;;
      6) run_step 'swap_manage' swap_manage ;;
      7) run_step 'snapshot_manage' snapshot_manage ;;
      8) run_step 'monitor_manage' monitor_manage ;;
      9) run_step 'script_update' script_update ;;
      10) run_step 'reset_saved_preferences' reset_saved_preferences ;;
      99) run_step 'novice_safe_repair' novice_safe_repair ;;
      q|Q) break ;;
      *) say '选择无效。' 'Invalid choice.' ;;
    esac
    pause
  done
}
