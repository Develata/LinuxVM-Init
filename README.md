# LinuxVM-Init

面向小白的 Linux VPS 初始化脚本（仅 Debian/Ubuntu）。

建议在**新服务器首次初始化**时使用本脚本，避免与历史配置冲突。

## 功能特点
- 必须手动选择系统版本（不自动识别）。
- 支持中英文交互。
- 每个可能有风险的步骤都会提前提示后果。
- 仅支持 Debian 系：`debian10/11/12/13`、`ubuntu22/ubuntu24`。

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

## 关键说明
- SSH 端口可手动输入或随机生成（`20000–60999`）。
- SSH 端口会检测占用状态，并过滤常见保留黑名单端口。
- 选择密钥登录后，会强制关闭密码登录。
- 防火墙支持 `ufw` 与 `iptables` 两种方案可选。
- Swap 会先做磁盘判断：当 `磁盘 < 内存 * 4` 时自动跳过。

## 常驻管理能力
- 菜单 `13) 常驻管理中心` 可反复进入，不只是一次性初始化。
- 防火墙管理：可按需放行/删除端口（`ufw` 或 `iptables`）。
- fail2ban 管理：可修改 `bantime/findtime/maxretry`，并手动封禁或解封 IP。
- Docker 管理：可查看状态、重启服务、调整日志限制。
- Swap 管理：可查看状态、重配或删除 swapfile。
- 自动安全更新管理：可启用或关闭 unattended-upgrades。

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

## 安全提示
本脚本会修改系统配置，请逐条阅读提示后再确认执行。

## 开源协议
本项目使用 MIT License，详见 `LICENSE`。
