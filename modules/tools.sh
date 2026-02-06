#!/usr/bin/env bash

tools_install() {
  say '风险提示：安装工具会占用少量磁盘空间。' 'Warning: installing tools uses disk space.'
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
