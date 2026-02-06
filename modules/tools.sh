#!/usr/bin/env bash

tools_install() {
  say '风险提示：安装工具会占用少量磁盘空间。' 'Warning: installing tools uses disk space.'
  say '说明：两个工具默认都不安装，直接回车就是跳过。需要安装请手动输入 y。' 'Note: both tools are skipped by default. Press Enter to skip, type y to install.'
  say '说明：vim 是编辑器；command-not-found 会在命令不存在时提示可安装的软件包。' 'Note: vim is an editor; command-not-found suggests installable packages for unknown commands.'
  local did_any='no'
  if confirm '安装 vim？[y/N]' 'Install vim? [y/N]'; then
    run_cmd 'apt install -y vim'
    did_any='yes'
  fi
  if confirm '安装 command-not-found？[y/N]' 'Install command-not-found? [y/N]'; then
    run_cmd 'apt install -y command-not-found'
    did_any='yes'
  fi
  if [ "$did_any" = 'no' ]; then
    return 2
  fi
}
