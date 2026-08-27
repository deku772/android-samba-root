---
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '691fe459-d380-4b49-a5a3-870f8c3ea2ec'
  PropagateID: '691fe459-d380-4b49-a5a3-870f8c3ea2ec'
  ReservedCode1: '71a942b7-0169-46b5-8c39-ffbb7d9bdf54'
  ReservedCode2: '71a942b7-0169-46b5-8c39-ffbb7d9bdf54'
---

# Android Samba (Root) — 已 root 安卓手机局域网文件共享

将已 root 的 Android 手机通过 Termux + Samba 变成无线移动硬盘，局域网内 Windows/macOS/Linux 可直接以 `\\手机IP\sdcard` 访问手机全部存储。

## 适用条件

| 条件 | 要求 |
|------|------|
| Root | 已 root（Magisk / KernelSU 等），能执行 `su` |
| Termux | 已安装 Termux（推荐 F-Droid 版） |
| 网络 | 手机与电脑在同一局域网（同一 WiFi） |
| 手机 | Android 10+，架构 arm64（其他架构需自行调整） |

---

## 一键脚本（推荐）

提供两种一键脚本，覆盖全自动和手动场景。

### 方式 A：电脑端全自动部署（推荐）

在 Windows 电脑上用 PowerShell 通过 ADB 一键完成推送、安装、配置、端口转发：

```powershell
git clone https://github.com/deku772/android-samba-root.git
cd android-samba-root

# 全自动部署（推送文件 → 安装 Samba → 配置 → iptables 端口转发）
.\deploy.ps1 -Auto

# 交互式部署（每步确认）
.\deploy.ps1

# 其他命令
.\deploy.ps1 -Status    # 查看手机端 Samba 运行状态
.\deploy.ps1 -Stop       # 停止手机端 Samba
.\deploy.ps1 -Test       # 从电脑测试 SMB 连接
```

> **注意**：`deploy.ps1` 能自动完成除启动 smbd 外的所有步骤。
> 最后一步需要你在手机上打开 Termux App 手动执行启动命令（脚本会提示）。
> 这是因为 Android 安全机制限制，ADB/su 启动的进程无法访问 /sdcard。

### 方式 B：手机端一键配置

如果已手动将仓库文件传到手机，或通过 SSH 在 Termux 中操作：

```bash
# 全自动配置（安装 → 配置 → 修复 tdb → iptables → 启动）
bash setup.sh --auto

# 交互式配置（每步确认）
bash setup.sh

# 其他命令
bash setup.sh --status   # 查看运行状态
bash setup.sh --stop      # 停止服务
bash setup.sh --help      # 显示帮助
```

`setup.sh` 自动完成 5 个步骤：

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 安装 Samba | `pkg install samba` |
| 2 | 写入配置 | 匿名共享 /sdcard，端口 4445 |
| 3 | 修复 tdb 权限 | 删除 root 属主的 tdb 文件，防止 smbd 崩溃 |
| 4 | iptables 端口转发 | 445 → 4445，让 Windows 直接访问（需 root） |
| 5 | 启动 smbd | 验证进程和端口，输出访问地址 |

---

## 手动分步操作

如果希望了解每一步细节，或一键脚本遇到问题，可按以下步骤手动操作。

### 1. 安装 Samba（在 Termux App 中执行）

```bash
pkg update -y && pkg install samba -y
smbd --version
```

### 2. 写入配置

```bash
cp $PREFIX/etc/samba/smb.conf $PREFIX/etc/samba/smb.conf.bak 2>/dev/null
# 将 config/smb-anonymous.conf 内容写入 $PREFIX/etc/samba/smb.conf
```

或将仓库中的 `config/smb-anonymous.conf` push 到手机：

```powershell
# 电脑端 PowerShell（ADB 连接手机后）
adb push config/smb-anonymous.conf /data/local/tmp/smb.conf
adb shell "su -c 'cp /data/local/tmp/smb.conf /data/data/com.termux/files/usr/etc/samba/smb.conf'"
adb shell "su -c 'chown 10475:10475 /data/data/com.termux/files/usr/etc/samba/smb.conf'"
```

### 3. 修复 tdb 权限（关键！）

root 操作产生的 tdb 文件属主是 root，会导致 smbd 崩溃。需删除让 Termux 用户重建：

```bash
# 在 Termux App 中执行
rm -f $PREFIX/var/lib/samba/account_policy.tdb
rm -f $PREFIX/var/lib/samba/group_mapping.tdb
rm -f $PREFIX/var/lib/samba/private/passdb.tdb
rm -f $PREFIX/var/lib/samba/private/secrets.tdb
```

### 4. 配置端口转发（需 root）

Termux 非 root 用户无法绑定 1024 以下端口，Samba 实际监听 4445。通过 iptables 将 445 转发到 4445，让 Windows 直接访问：

```bash
# 在手机 root shell 中执行
iptables -t nat -A PREROUTING -p tcp --dport 445 -j REDIRECT --to-ports 4445
iptables -t nat -A OUTPUT -p tcp --dport 445 -j REDIRECT --to-ports 4445
```

### 5. 启动 Samba（必须在 Termux App 中执行！）

```bash
# 在 Termux App 中执行，不能通过 ADB/su 启动
smbd -D
```

### 6. 获取手机 IP

```bash
ip addr show wlan0 | grep "inet "
```

### 7. 电脑访问

Windows 资源管理器地址栏输入：

```
\\手机IP\sdcard
```

例如 `\\192.168.1.93\sdcard`，无需密码，直接访问。

---

## 重要注意事项

### 为什么必须在 Termux App 中手动启动 smbd？

这是本方案最关键的限制。Android 安全机制导致：

- **ADB/su 启动的进程**：SELinux 上下文为 `u:r:ksu:s0`，**无法访问 /sdcard**（报 `canonicalize_connect_path failed`）
- **Termux App 内启动的进程**：SELinux 上下文为 `u:r:untrusted_app_27:s0`，**可以访问 /sdcard**

只有 Termux App 自身启动的进程才有正确的 SELinux 上下文，能同时读取 Samba 配置和访问 /sdcard。

### tdb 文件权限

Samba 的 tdb 数据库文件必须由 Termux 用户（UID 10475）拥有。如果 root 操作产生了 root 属主的 tdb 文件，smbd 会崩溃。解决方法是删除旧文件，让 Termux 用户在首次启动时自动重建。

### iptables 规则重启后失效

iptables 规则在手机重启后消失。如需持久化，可用 Magisk 模块或 init.d 脚本。

### smbd 进程重启后需手动启动

Termux 不是系统服务，smbd 进程在手机重启后不会自动运行。可配合 Termux:Boot 插件实现开机自启。

## 安全提醒

- **匿名共享整个 /sdcard**：同一 WiFi 下任何设备都能访问手机全部文件，包括照片、应用数据
- 建议只在可信局域网使用，用完后关闭 smbd：`bash setup.sh --stop`
- 如需更安全的配置，可设置用户名密码访问

## 仓库结构

```
android-samba-root/
├── setup.sh                   # ★ 一键配置脚本（手机端，Termux 中执行）
├── deploy.ps1                  # ★ 一键部署脚本（电脑端，PowerShell 中执行）
├── README.md                   # 本说明文档
├── config/
│   └── smb-anonymous.conf      # 匿名共享 /sdcard 配置模板
├── scripts/
│   ├── install.sh              # 安装 Samba（Termux 中执行）
│   ├── setup-config.sh         # 写入配置并修复 tdb 权限（Termux 中执行）
│   ├── start-smbd.sh           # 启动 Samba 服务（Termux 中执行）
│   ├── stop-smbd.sh            # 停止 Samba 服务（Termux 中执行）
│   ├── port-forward.sh         # iptables 445→4445 端口转发（root shell 中执行）
│   └── status.sh               # 检查 Samba 运行状态（Termux 中执行）
└── docs/
    └── troubleshooting.md      # 常见问题排查
```

## 测试环境

- 手机：红米 K20 Pro (raphael)，Android SDK 36
- Root：KernelSU Next v3.2.0
- Termux：0.118.3.58（F-Droid）
- Samba：4.16.11
- 电脑：Windows 11 + PowerShell 5.1
- 验证方式：smbprotocol 协议握手 + Windows `net use` + `dir \\IP\sdcard`

## 许可

MIT

> AI生成