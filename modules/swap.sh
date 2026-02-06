#!/usr/bin/env bash

swap_setup() {
  say '风险提示：Swap 使用磁盘，磁盘过小可能导致系统满盘。' 'Warning: swap uses disk; small disks may fill up.'

  local mem_kb disk_kb mem_mb disk_mb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  disk_kb="$(df -k / | awk 'NR==2 {print $2}')"
  mem_mb=$((mem_kb / 1024))
  disk_mb=$((disk_kb / 1024))

  if [ "$disk_mb" -lt $((mem_mb * 4)) ]; then
    say '磁盘太小（磁盘 < 内存*4），已跳过。' 'Disk too small (disk < memory*4), skipping.'
    return 2
  fi

  local suggested
  suggested=$((mem_mb * 2))
  if [ "$suggested" -gt 4096 ]; then
    suggested=4096
  fi

  local input_mb
  say "建议 swap 大小：${suggested}MB" "Suggested swap size: ${suggested}MB"
  ask '输入 swap 大小(MB)，回车使用建议值：' 'Enter swap size in MB, Enter to accept:' input_mb
  if [ -z "$input_mb" ]; then
    input_mb="$suggested"
  fi
  if ! [[ "$input_mb" =~ ^[0-9]+$ ]] || [ "$input_mb" -lt 256 ]; then
    say 'swap 大小无效，取消操作。' 'Invalid swap size, aborting.'
    return 1
  fi

  run_cmd 'swapoff -a'
  run_cmd "dd if=/dev/zero of=/root/swapfile bs=1M count=$input_mb"
  run_cmd 'chmod 600 /root/swapfile'
  run_cmd 'mkswap /root/swapfile'
  run_cmd 'swapon /root/swapfile'

  if ! grep -q '/root/swapfile' /etc/fstab; then
    printf '%s\n' '/root/swapfile swap swap defaults 0 0' >>/etc/fstab
  fi
  say 'Swap 配置完成。' 'Swap setup complete.'
}
