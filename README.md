---
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '3169a92c-af30-4827-bcbd-872ea15bf9af'
  PropagateID: '3169a92c-af30-4827-bcbd-872ea15bf9af'
  ReservedCode1: '4f098753-800b-4406-b94d-ea8a38dc06c3'
  ReservedCode2: '4f098753-800b-4406-b94d-ea8a38dc06c3'
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
> 这是因为 Android 安全机制限制，ADB/su 启动的进程需要指定补充组才能访问 /sdcard。

### 方式 B：手机端一键配置

如果已手动将仓库文件传到手机，或通过 SSH 在 Termux 中操作：

```bash
# 全自动配置（安装 → 配置 → 修复 tdb → iptables → 启动 → 迅雷挂载）
bash setup.sh --auto

# 交互式配置（每步确认）
bash setup.sh

# 其他命令
bash setup.sh --status   # 查看运行状态
bash setup.sh --stop      # 停止服务
bash setup.sh --xunlei    # 单独挂载迅雷下载目录
bash setup.sh --help      # 显示帮助
```

`setup.sh` 自动完成 6 个步骤：

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 安装 Samba | `pkg install samba` |
| 2 | 写入配置 | 匿名共享 /sdcard + 迅雷下载目录，端口 4445 |
| 3 | 修复 tdb 权限 | 删除 root 属主的 tdb 文件，防止 smbd 崩溃 |
| 4 | iptables 端口转发 | 445 → 4445，让 Windows 直接访问（需 root） |
| 5 | 启动 smbd | 验证进程和端口，输出访问地址 |
| 6 | 挂载迅雷下载目录 | bind mount + 修复父目录权限（可选，需 root） |

---

## 共享路径

| 共享名 | 路径 | 说明 |
|--------|------|------|
| `sdcard` | `/sdcard` | 手机内置存储（直接可用） |
| `xunlei` | `/data/local/tmp/xunlei_download` | 迅雷下载目录（需先执行 mount-xunlei.sh） |

访问方式：`\\手机IP\sdcard` 或 `\\手机IP\xunlei`，例如 `\\192.168.1.93\sdcard`

---

## 迅雷下载目录共享

迅雷无法修改下载目录，默认保存在 `/sdcard/Android/data/com.xunlei.downloadprovider/files/ThunderDownload`。由于 Android 11+ Scoped Storage 限制，smbd 无法直接访问其他应用的 `Android/data` 目录。

### 解决方案

通过 `mount --bind` 将迅雷下载目录映射到 `/data/local/tmp/xunlei_download`（ext4 层），并修复整个父目录链的 ext4 权限为 777：

```bash
# 在手机 root shell 中执行
adb push scripts/mount-xunlei.sh /sdcard/
adb shell "su -c 'sh /sdcard/mount-xunlei.sh'"
```

或通过 setup.sh 一键执行：

```bash
bash setup.sh --xunlei
```

> **注意**：bind mount 和父目录权限修复在手机重启后失效，需重新执行。

### 技术原理

1. **为什么不能直接共享 `Android/data` 下的目录？** smbd 的 SELinux 上下文是 `untrusted_app_27`，Android 11+ Scoped Storage 阻止它访问其他应用的 `Android/data` 目录。

2. **为什么 bind mount 到 `/sdcard` 下不行？** `/sdcard` 是 sdcardfs（FUSE）挂载，`mask=6` 限制了 "other" 用户权限为 `--x`（可穿越不可列出），chmod 无效。

3. **为什么 bind mount 到 `/data/local/tmp` 可以？** 这是 ext4 层面的直接挂载，不经过 sdcardfs，文件权限由 ext4 控制。修复父目录链权限为 777 后，smbd 即可正常访问。

4. **为什么要修复父目录链权限？** Linux 要求从根目录到目标文件的每一级父目录都必须可穿越（`+x`），任何一级不可穿越都会导致 Access Denied。

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
# 在 Termux App 中执行
smbd -D
```

如果通过 su 启动，必须指定补充组（否则 /sdcard 无法访问）：

```bash
# su 启动方式（需要补充组才能访问 /sdcard 符号链接）
su 10475 -G 3003 -G 9997 -G 20475 -G 50475 -c "smbd -D"
```

### 6. 挂载迅雷下载目录（可选，需 root）

```bash
# 在手机 root shell 中执行
adb push scripts/mount-xunlei.sh /sdcard/
adb shell "su -c 'sh /sdcard/mount-xunlei.sh'"
# 然后重启 smbd
```

### 7. 获取手机 IP

```bash
ip addr show wlan0 | grep "inet "
```

### 8. 电脑访问

Windows 资源管理器地址栏输入：

```
\\手机IP\sdcard       — 内置存储
\\手机IP\xunlei       — 迅雷下载目录
```

例如 `\\192.168.1.93\sdcard`，无需密码，直接访问。

---

## 重要注意事项

### 为什么 smbd 需要补充组？

`/sdcard` 是指向 `/storage/self/primary` 的符号链接。smbd 在 `canonicalize_connect_path` 时需要解析这个链接，但 `/storage/self/` 目录权限为 `drwx--x---`（属主 shell:everybody），只有 `everybody` 组（GID 9997）的成员才能穿越。Termux App 内启动的进程自动拥有补充组 `3003 9997 20475 50475`，但通过 `su` 启动时这些组会丢失，必须用 `su -G` 手动指定。

### 为什么必须在 Termux App 中启动 smbd？

- **ADB/su 启动的进程**：SELinux 上下文为 `u:r:ksu:s0`，无法访问 /sdcard
- **Termux App 内启动的进程**：SELinux 上下文为 `u:r:untrusted_app_27:s0`，可以访问 /sdcard

只有 Termux App 自身启动的进程才有正确的 SELinux 上下文和补充组。

### tdb 文件权限

Samba 的 tdb 数据库文件必须由 Termux 用户（UID 10475）拥有。如果 root 操作产生了 root 属主的 tdb 文件，smbd 会崩溃。解决方法是删除旧文件，让 Termux 用户在首次启动时自动重建。

### iptables 规则重启后失效

iptables 规则在手机重启后消失。如需持久化，可用 Magisk 模块或 init.d 脚本。

### bind mount 重启后失效

迅雷下载目录的 bind mount 和父目录权限修复在手机重启后失效。需重新执行 `mount-xunlei.sh` 或 `bash setup.sh --xunlei`。

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
│   └── smb-anonymous.conf      # 匿名共享 /sdcard + 迅雷下载目录 配置模板
├── scripts/
│   ├── install.sh              # 安装 Samba（Termux 中执行）
│   ├── setup-config.sh         # 写入配置并修复 tdb 权限（Termux 中执行）
│   ├── start-smbd.sh           # 启动 Samba 服务（Termux 中执行）
│   ├── stop-smbd.sh            # 停止 Samba 服务（Termux 中执行）
│   ├── port-forward.sh         # iptables 445→4445 端口转发（root shell 中执行）
│   ├── mount-xunlei.sh         # 挂载迅雷下载目录（root shell 中执行）
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