# LinuxVM-Init

面向小白的 Linux VPS 初始化脚本（仅 Debian/Ubuntu）。

建议在**新服务器首次初始化**时使用本脚本，避免与历史配置冲突。

## 功能特点
- 必须手动选择系统版本（不自动识别）。
- 支持中英文交互。
- 每个可能有风险的步骤都会提前提示后果。
- 仅支持 Debian 系：`debian10/11/12/13`、`ubuntu22/ubuntu24`。

## 脚本会做什么
- 系统初始化：更新软件包、安装常用工具、可选创建普通用户并加入 sudo。
- SSH 安全：可选修改 SSH 端口、调整 root/密码/密钥登录策略，并在变更后给出测试命令。
- 防火墙：支持 `ufw` 与 `iptables`，启用前强制检测并放行 SSH 端口。
- Fail2ban：可安装并配置防爆破策略，支持手动封禁/解封 IP。
- 运行环境：可选安装 Docker、配置 Docker 日志限制、配置 Swap、启用自动安全更新。
- Docker 安装流程会同时检测并安装 Docker Compose（优先 compose 插件）。
- 面板运维：主菜单分模块管理（SSH/防火墙/fail2ban/Docker/Swap/系统维护），可长期反复使用。
- 安全兜底：关键变更前会创建快照，支持按快照 ID 回滚；并记录执行日志与结果汇总。

## 使用方式
仓库地址：`https://github.com/Develata/LinuxVM-Init.git`
维护者 GitHub ID：`Develata`

1. 保持当前 SSH 会话不断开。
2. 在服务器上拉取项目：

```bash
apt install git # 防止没有git
git clone https://github.com/Develata/LinuxVM-Init.git
cd LinuxVM-Init
```

3. 赋予执行权限并运行：

```bash
chmod +x vps-init.sh
sudo bash vps-init.sh
```

也可以安装全局命令 `lvm`（推荐）：

```bash
sudo bash install.sh
lvm
```

说明：若系统中已存在非软链接的 `lvm` 命令，安装脚本会拒绝覆盖并提示你手动处理。
脚本启动时也会尝试自动安装 `lvm`；若检测到已存在 `lvm` 命令，会提示你手动处理，不会强制覆盖。
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
- 防火墙后端（仅非交互且启用防火墙时）：`NI_FIREWALL_MODE=ufw` 或 `NI_FIREWALL_MODE=iptables`

## 关键说明
- SSH 端口可手动输入或随机生成（`20000–60999`）。
- SSH 端口会检测占用状态，并过滤常见保留黑名单端口。
- SSH 相关高风险操作默认跳过，需手动确认后才执行。
- 选择密钥登录后，会强制关闭密码登录。
- 防火墙支持 `ufw` 与 `iptables` 两种方案可选。
- 防火墙模式会持久化记录在 `/etc/linuxvm-init/state.env`。
- 防火墙与 fail2ban 变更时会优先保护当前来源 IP（可检测时）。
- 当检测到主机内存小于 1G 时，默认跳过 Docker 安装。
- 若内存小于 1G，仍可在主菜单 `2) Docker 管理面板` 中手动确认“强制安装”。
- Swap 会先做磁盘判断：当 `磁盘 < 内存 * 4` 时自动跳过。
- 若你在手动执行系统更新时遇到 `sshd_config` 冲突提示，对小白场景可直接一路回车（默认保留当前本地配置）。

## 常驻管理能力
- 主菜单 `0) Init 一键顺序配置`：按推荐顺序执行初始化。
- 主菜单 `1) SSH 管理面板`：SSH 相关操作全部集中管理。
- 主菜单 `2) Docker 管理面板`：Docker 安装、Compose、代理、日志限制统一管理。
- 主菜单 `3) 防火墙管理面板`：`ufw` 与 `iptables` 的规则和策略管理。
- 主菜单 `4) fail2ban 管理面板`：支持安装/初始化、策略调整、封禁与解封 IP。
- 主菜单 `5) 系统维护`：系统更新、工具、用户、自动更新管理、logrotate、1panel。
- 主菜单 `6) Swap 管理`：查看/重配/删除 swap。
- 主菜单 `7) 快照与回滚`：按时间戳创建、查看、回滚配置。
- 主菜单 `8) 巡检与每日简报`：cron 每日报告与手动巡检。
- 主菜单 `9) 脚本更新`：更新前自动创建本地快照；检测到本地改动时可自动 stash 后再更新。
- 主菜单 `10) 清空已记住的语言/系统`：清空偏好，下次启动重新询问。
- 主菜单 `99) 新手一键修复（安全模式）`：应急修复 SSH/防火墙/fail2ban 可用性。
- 主菜单顶部会显示版本信息：当前脚本版本与最新版本（基于 git）。
- 快照自动清理：默认仅保留最近 14 天快照，旧快照在创建新快照时自动清理。

### Init 步骤提示（与面板一致）
- 每一步都会单独询问是否执行（`y/N`），不需要的步骤可直接回车跳过。
- 步骤 1/8：系统更新（更新软件包索引并安装可升级项，可能耗时）。
- 步骤 2/8：常用工具（`vim` 和 `command-not-found` 默认跳过，直接回车即可）。
- 步骤 3/8：创建普通用户（先输入用户名，再设置密码；资料项可连续回车，最后输入 `Y` 确认）。
- 步骤 4/8：SSH 与防火墙（若启用 SSH 设置，只需选一次端口，然后配置防火墙并应用 SSH）。
- 步骤 5/8：fail2ban（默认参数较保守，连续失败登录会触发封禁）。
- 步骤 6/8：自动安全更新（启用后系统会自动执行安全更新）。
- 步骤 7/8：Swap（可选，不需要可直接回车跳过）。
- 步骤 8/8：1panel（可选，不需要可直接回车跳过）。

## 项目结构
- `vps-init.sh`：主入口脚本（菜单与流程）
- `VERSION`：脚本语义化版本号（例如 `v1.0.0`）
- `install.sh`：安装全局命令 `lvm`
- `uninstall.sh`：卸载全局命令 `lvm`
- `lib/common.sh`：公共入口（聚合通用方法）
- `lib/common_ui.sh`：交互与提示
- `lib/common_exec.sh`：命令执行、校验、来源 IP 检测
- `lib/common_state.sh`：状态持久化、执行汇总、回滚提示
- `modules/panel_args.sh`：参数解析、系统选择、非交互入口
- `modules/panel_menu.sh`：主菜单与 Init 流程
- `modules/ssh_common.sh`：SSH 公共能力（端口检测、配置写入）
- `modules/ssh_port.sh`：SSH 端口与 root 登录策略
- `modules/ssh_auth.sh`：SSH 密钥登录策略
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

自检覆盖：脚本语法、模块加载、关键函数可用性、基础命令可用性。

## 安全提示
本脚本会修改系统配置，请逐条阅读提示后再确认执行。

## 开源协议
本项目使用 MIT License，详见 `LICENSE`。
