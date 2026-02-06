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
- 常驻运维：提供管理中心（SSH/防火墙/fail2ban/Docker/Swap/自动更新）可长期反复使用。
- 安全兜底：关键变更前会创建快照，支持按快照 ID 回滚；并记录执行日志与结果汇总。

## 使用方式
仓库地址：`https://github.com/Develata/LinuxVM-Init.git`

1. 保持当前 SSH 会话不断开。
2. 在服务器上拉取项目：

```bash
git clone https://github.com/Develata/LinuxVM-Init.git
cd LinuxVM-Init
```

3. 赋予执行权限并运行：

```bash
chmod +x vps-init.sh
sudo bash vps-init.sh
```

4. SSH 相关操作完成后，先在新终端测试再断开旧连接：

```bash
ssh -p 新端口 用户名@服务器IP
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
- 若内存小于 1G，仍可在常驻管理中心进入 Docker 管理后手动确认“强制安装”。
- Swap 会先做磁盘判断：当 `磁盘 < 内存 * 4` 时自动跳过。

## 常驻管理能力
- 菜单 `13) 常驻管理中心` 可反复进入，不只是一次性初始化。
- SSH 管理：可查看配置摘要、单独改端口、改 root/密码/密钥登录策略、查看失败日志。
- 防火墙管理：可按需放行/删除端口（`ufw` 或 `iptables`）。
- fail2ban 管理：可修改 `bantime/findtime/maxretry`，并手动封禁或解封 IP。
- Docker 管理：可查看状态、重启服务、调整日志限制。
- Docker 管理：支持设置/清除代理，解决部分地区无法访问 Docker 的问题。
 - Docker 管理：支持安装/修复 Docker Compose。
- Swap 管理：可查看状态、重配或删除 swapfile。
- 自动安全更新管理：可启用或关闭 unattended-upgrades。
- 快照与回滚：可按时间戳创建/查看/恢复系统关键配置。
- 巡检与每日简报：支持 cron 每日报告与手动巡检。
- 快照自动清理：默认仅保留最近 14 天快照，旧快照会在创建新快照时自动清理。
- 主菜单 `99) 新手一键修复（安全模式）`：用于应急修复 SSH/防火墙/fail2ban 的可用性。

## 项目结构
- `vps-init.sh`：主入口脚本（菜单与流程）
- `lib/common.sh`：公共方法（多语言、日志、交互、备份）
- `modules/ssh_common.sh`：SSH 公共能力（端口检测、配置写入）
- `modules/ssh_port.sh`：SSH 端口与 root 登录策略
- `modules/ssh_auth.sh`：SSH 密钥登录策略
- `modules/`：其他功能模块（防火墙、Docker、swap、fail2ban 等）

## 执行反馈
- 退出脚本时会输出本次执行汇总（成功/跳过/失败）。
- 退出脚本时会输出常见回滚命令提示。

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
