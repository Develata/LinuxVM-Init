# LinuxVM-Init

面向小白的 Linux VPS 初始化脚本（仅 Debian/Ubuntu）。

建议在**新服务器首次初始化**时使用本脚本，避免与历史配置冲突。

## 功能特点
- 启动时会自动检测系统版本并询问确认（也可手动改选）。
- 支持中英文交互。
- 每个可能有风险的步骤都会提前提示后果。
- 仅支持 Debian 系：`debian10/11/12/13`、`ubuntu22/ubuntu24`。

## 脚本会做什么
- 系统初始化：更新软件包、安装常用工具、可选创建普通用户并加入 sudo。
- SSH 安全：可选修改 SSH 端口、调整 root/密码/密钥登录策略，并在变更后给出测试命令。
- 防火墙：统一使用 `nftables`，启用前强制检测并放行 SSH 端口，同时覆盖 IPv4/IPv6；自定义放行规则区分 TCP、UDP、ICMP。
- Fail2ban：可安装并配置防爆破策略，支持手动封禁/解封 IP。
- 运行环境：可选安装 Docker、配置 Docker 日志限制、配置 Swap、启用自动安全更新。
- Docker 安装流程会同时检测并安装 Docker Compose（优先 compose 插件）。
- 面板运维：主菜单分模块管理（SSH/防火墙/fail2ban/Docker/Swap/系统维护），可长期反复使用。
- 安全兜底：关键变更前会创建快照，支持按快照 ID 回滚；并记录执行日志与结果汇总。
- 第三方安装脚本（Docker/1Panel）会先下载到本地、输出 SHA256，再二次确认执行。

## 使用方式
仓库地址：`https://github.com/Develata/LinuxVM-Init.git`
维护者 GitHub ID：`Develata`

1. 保持当前 SSH 会话不断开。
2. 在服务器上拉取项目：

```bash
apt update # 更新一下apt
apt install git # 防止没有git
git clone https://github.com/Develata/LinuxVM-Init.git
cd LinuxVM-Init
```

3. 赋予执行权限并运行：

root用户就直接去掉sudo

```bash
chmod +x vps-init.sh
sudo bash vps-init.sh
```

也可以安装全局命令 `lvm`（推荐）：

```bash
sudo bash install.sh
lvm
```

说明：安装脚本会在 `/usr/local/bin/lvm` 创建一个 wrapper 脚本（非软链接），指向当前仓库的 `vps-init.sh`。
若已存在由其他 LinuxVM-Init 仓库创建的 `lvm`（旧版软链接或 wrapper 脚本），会自动替换为当前仓库路径。
若系统中已有非项目管理的 `lvm` 文件，安装脚本会拒绝覆盖并提示你手动处理。
脚本启动时也会尝试自动安装 `lvm`；若检测到已存在非项目管理的 `lvm` 命令，会提示你手动处理，不会强制覆盖。
脚本会记住你首次选择的语言和系统版本，后续执行 `lvm` 不再重复询问（可用参数覆盖）。

4. SSH 相关操作完成后，先在新终端测试再断开旧连接：

```bash
ssh -p 新端口 用户名@服务器IP
```

如需卸载全局命令：

```bash
sudo bash uninstall.sh
```

## 批处理模式（非交互）
用于自动化部署（默认执行推荐子集，SSH 仍建议人工处理）：

```bash
sudo bash vps-init.sh --non-interactive --distro ubuntu24
```

可选参数：
- `--lang en`：英文输出
- `--yes`：自动确认
- 环境开关：`NI_RUN_SYSTEM_UPDATE=1 NI_RUN_TOOLS=1 NI_RUN_FIREWALL=0 NI_RUN_FAIL2BAN=0 NI_RUN_UNATTENDED=1`
- 防火墙后端已固定为 `nftables`；旧的 `NI_FIREWALL_MODE=ufw/iptables` 会被忽略并提示。

## 关键说明
- SSH 端口可手动输入或随机生成（`20000–60999`）。
- SSH 端口会检测占用状态，并过滤常见保留黑名单端口。
- SSH 相关高风险操作默认跳过，需手动确认后才执行。
- 选择密钥登录后，会强制关闭密码登录。
- 防火墙统一使用 `nftables`，通过 `inet` 表同时管理 IPv4/IPv6。
- 防火墙放行规则按协议分别管理：TCP/UDP 需要端口，ICMP 默认仅放行诊断、PMTU 与 IPv6 邻居发现所需类型。
- FORWARD 链默认 DROP，但会保留 Docker bridge 常见流量兼容规则，避免破坏容器网络。
- 防火墙模式会持久化记录在 `/etc/linuxvm-init/state.env`。
- 检测到旧 `ufw` / `iptables-persistent` 配置时，会先保存旧规则到 `/etc/linuxvm-init/legacy-firewall-backups/`，确认后再禁用旧防火墙服务并切换到 nftables。
- 防火墙与 fail2ban 变更时会优先保护当前来源 IP（可检测时）。
- 当检测到主机内存小于 1G 时，默认跳过 Docker 安装。
- 若内存小于 1G，仍可在主菜单 `2) Docker 管理面板` 中手动确认“强制安装”。
- Swap 会先做磁盘判断：当 `磁盘 < 内存 * 4` 时自动跳过。
- 若你在手动执行系统更新时遇到 `sshd_config` 冲突提示，对小白场景可直接一路回车（默认保留当前本地配置）。

## 常驻管理能力
- 主菜单 `0) Init 一键顺序配置`：按推荐顺序执行初始化。
- 主菜单 `1) SSH 管理面板`：SSH 相关操作全部集中管理。
- 主菜单 `2) Docker 管理面板`：Docker 安装、Compose、代理、日志限制统一管理。
- 主菜单 `3) 防火墙管理面板`：nftables 状态与规则查看、TCP/UDP/ICMP 放行与删除、配置重载。
- 主菜单 `4) fail2ban 管理面板`：支持安装/初始化、策略调整、封禁与解封 IP。
- 主菜单 `5) 系统维护`：系统更新、工具、用户、自动更新管理、logrotate、1panel。
- 主菜单 `6) Swap 管理`：查看/重配/删除 swap。
- 主菜单 `7) 快照与回滚`：按时间戳创建、查看、回滚配置。
- 主菜单 `8) 巡检与每日简报`：cron 每日报告与手动巡检。
- 主菜单 `9) 脚本更新`：更新前自动创建本地快照；检测到本地改动时可自动 stash；更新后自动运行自检，失败会回滚到更新前提交。
- 主菜单 `10) 清空已记住的语言/系统`：清空偏好，下次启动重新询问。
- 主菜单 `99) 新手一键修复（安全模式）`：应急修复 SSH/防火墙/fail2ban 可用性。
- 主菜单顶部会显示版本信息：当前脚本版本与最新版本（基于 git）。
- 快照自动清理：默认仅保留最近 14 天快照，旧快照在创建新快照时自动清理。
- 快照会覆盖 SSH、ssh.socket drop-in、nftables、旧 UFW/iptables 规则备份、fail2ban、Docker、Docker systemd 代理、自动更新、`/etc/fstab` 与脚本状态文件。

### Init 步骤提示（与面板一致）
- 每一步都会单独询问是否执行（`y/N`），不需要的步骤可直接回车跳过。
- 步骤 1/8：系统更新（更新软件包索引并安装可升级项，可能耗时）。
- 步骤 2/8：常用工具（`vim` 和 `command-not-found` 默认跳过，直接回车即可）。
- 步骤 3/8：创建普通用户（先输入用户名，再单独执行密码设置；不再要求填写姓名/电话等资料项）。
- 步骤 4/8：SSH 与防火墙（若启用 SSH 设置，只需选一次端口，然后配置防火墙并应用 SSH）。
- 步骤 5/8：fail2ban（默认参数较保守，连续失败登录会触发封禁）。
- 步骤 6/8：自动安全更新（启用后系统会自动执行安全更新）。
- 步骤 7/8：Swap（可选，不需要可直接回车跳过）。
- 步骤 8/8：1panel（可选，不需要可直接回车跳过）。

### 1Panel 官方安装命令
当前 1Panel v2 官方在线安装命令为：

```bash
bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
```

脚本内不会直接使用管道执行；会下载该脚本到临时文件，显示 SHA256 后再确认执行。

## 应急恢复 SSH
如果误改 SSH 或防火墙导致无法登录，优先通过云厂商 VNC/救援模式进入服务器，然后按实际情况执行：

```bash
cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
rm -f /etc/systemd/system/ssh.socket.d/override.conf
systemctl daemon-reload
systemctl restart sshd || systemctl restart ssh
nft list table inet linuxvm_init
ls -la /etc/linuxvm-init/legacy-firewall-backups/
```

如果使用了脚本快照，可运行 `lvm` 后进入 `7) 快照与回滚` 按快照 ID 恢复。

## 项目结构
- `vps-init.sh`：主入口脚本（菜单与流程）
- `VERSION`：脚本语义化版本号（例如 `v1.0.0`）
- `install.sh`：安装全局命令 `lvm`（创建 wrapper 脚本）
- `uninstall.sh`：卸载全局命令 `lvm`
- `selfcheck.sh`：发布前自检脚本（语法、模块加载、关键函数可用性）
- `lib/common.sh`：公共入口（聚合通用方法）
- `lib/common_ui.sh`：交互与提示
- `lib/common_exec.sh`：命令执行、校验、来源 IP 检测
- `lib/common_state.sh`：状态持久化、执行汇总、回滚提示
- `modules/panel_args.sh`：参数解析、系统选择、非交互入口
- `modules/panel_menu.sh`：主菜单与 Init 流程
- `modules/ssh_common.sh`：SSH 公共能力（端口检测、配置写入）
- `modules/ssh_port.sh`：SSH 端口与 root 登录策略
- `modules/ssh_auth.sh`：SSH 密钥登录策略
- `modules/firewall.sh`：nftables 防火墙初始化、迁移与规则生成
- `modules/panel_main.sh`：模块入口聚合（source 所有子模块）
- `modules/`：其他功能模块（防火墙、Docker、swap、fail2ban 等）

## 执行反馈
- 退出脚本时会输出本次执行汇总（成功/跳过/失败）。
- 退出脚本时会输出常见回滚命令提示。

## 版本说明
- 面板默认优先显示 `VERSION` 文件中的版本号（如 `v1.0.0`）。
- 若缺少 `VERSION` 文件，才会回退显示 git 短哈希。

## 发布前标准命令
每次准备发布前，统一执行以下自检命令：

```bash
chmod +x selfcheck.sh
./selfcheck.sh
```

自检覆盖：脚本语法、ShellCheck（如已安装）、模块加载、关键函数可用性、基础命令可用性。

GitHub Actions 会在 push / pull request 时运行自检，并使用 Debian 12 与 Ubuntu 24.04 容器执行非交互入口冒烟测试。

## 安全提示
本脚本会修改系统配置，请逐条阅读提示后再确认执行。

## 开源协议
本项目使用 MIT License，详见 `LICENSE`。
