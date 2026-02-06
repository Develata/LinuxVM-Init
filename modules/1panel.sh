#!/usr/bin/env bash

onepanel_install() {
  say '风险提示：1panel 会安装面板服务并修改系统环境。' 'Warning: 1panel installs services and modifies system environment.'
  if ! confirm '是否安装 1panel？[y/N]' 'Install 1panel? [y/N]'; then
    return 2
  fi
  run_cmd 'bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"'
}
