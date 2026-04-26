#!/usr/bin/env bash

onepanel_install() {
  say '风险提示：1panel 会安装面板服务并修改系统环境。' 'Warning: 1panel installs services and modifies system environment.'
  if ! confirm '是否安装 1panel？[y/N]' 'Install 1panel? [y/N]'; then
    return 2
  fi
  say '官方安装命令：bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"' 'Official install command: bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"'
  log_line '>> bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)" (1panel official install)'
  download_and_run_script '1Panel' 'https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh' bash
}
