---
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: 'c3a096a3-5de2-4a16-8f82-309648563fca'
  PropagateID: 'c3a096a3-5de2-4a16-8f82-309648563fca'
  ReservedCode1: '1cb93548-cc82-4bba-999b-ab2d88420811'
  ReservedCode2: '1cb93548-cc82-4bba-999b-ab2d88420811'
---

# 常见问题排查

## 1. smbd 启动后无法访问 /sdcard

**症状**：smbd 进程在运行，端口 4445 也在监听，但连接共享时报错 `canonicalize_connect_path failed` 或 `NT_STATUS_ACCESS_DENIED`。

**原因**：smbd 进程的 SELinux 上下文不正确。通过 ADB 或 su 启动的进程上下文为 `u:r:ksu:s0`，无法访问 /sdcard。

**解决**：
```bash
# 必须在 Termux App 中手动启动，不能通过 ADB/su 启动
smbd -D
```

验证进程上下文：
```bash
# 在 Termux 中执行
cat /proc/$(pidof smbd)/attr/current
# 应显示 u:r:untrusted_app_27:s0:...  而非 u:r:ksu:s0
```

## 2. smbd 启动后立即崩溃

**症状**：`ps -ef | grep smbd` 看不到进程，或日志中有 `tdb` 相关错误。

**原因**：tdb 文件属主是 root（由 root 操作产生），Termux 用户无法读写。

**解决**：
```bash
# 在 Termux App 中执行
rm -f $PREFIX/var/lib/samba/account_policy.tdb
rm -f $PREFIX/var/lib/samba/group_mapping.tdb
rm -f $PREFIX/var/lib/samba/private/passdb.tdb
rm -f $PREFIX/var/lib/samba/private/secrets.tdb

# 重新启动
smbd -D
```

## 3. Windows 资源管理器无法连接 `\\手机IP\sdcard`

**症状**：Windows 提示找不到网络路径，但 `Test-NetConnection 手机IP -Port 4445` 成功。

**原因**：Windows SMB 客户端默认只连接 445 端口，而 Samba 监听的是 4445。

**解决**：配置 iptables 端口转发（需 root）：
```bash
# 在手机 root shell 中执行
iptables -t nat -A PREROUTING -p tcp --dport 445 -j REDIRECT --to-ports 4445
iptables -t nat -A OUTPUT -p tcp --dport 445 -j REDIRECT --to-ports 4445
```

验证：`Test-NetConnection 手机IP -Port 445` 应返回 `TcpTestSucceeded=True`。

## 4. `net view \\手机IP` 报"拒绝访问"

**症状**：`net view` 失败但 `dir \\手机IP\sdcard` 成功。

**原因**：`net view` 需要 RPC 枚举共享列表，匿名 guest 账户无此权限。这是正常行为。

**解决**：直接使用 `dir \\手机IP\sdcard` 或映射网络驱动器，跳过 `net view`。

## 5. PowerShell 中通过 ADB 执行复杂命令失败

**症状**：`adb shell "su -c 'command'"` 嵌套引号断裂，命令无法正确执行。

**原因**：PowerShell → ADB → su → sh 多层引号转义冲突。

**解决**：将命令写入 .sh 脚本文件，push 到手机后执行：
```powershell
# 电脑端
adb push script.sh /data/local/tmp/
adb shell "su -c 'sh /data/local/tmp/script.sh'"
```

## 6. iptables 规则执行报错

**症状**：`iptables` 命令报 `Permission denied` 或 `Table does not exist`。

**原因**：
- 未使用 root 权限执行
- 内核未编译 netfilter 模块（某些定制 ROM）

**解决**：
```bash
# 确认以 root 执行
su -c "iptables -t nat -L"
```

如果内核不支持 iptables NAT，可改用支持自定义端口的 SMB 客户端（如 RaiDrive）直接连接 4445 端口。

## 7. 手机重启后所有配置丢失

**症状**：重启手机后 smbd 不运行，iptables 规则消失。

**原因**：Termux 不是系统服务，iptables 规则也不持久化。

**解决**：
1. 重新执行 `scripts/port-forward.sh`（root shell）
2. 打开 Termux App 执行 `scripts/start-smbd.sh`
3. 如需自动化，安装 Termux:Boot 插件，将启动脚本放入 `~/.termux/boot/`

## 8. Samba 配置中 smb ports 设为 445 但实际监听 4445

**说明**：如果 `smb.conf` 中 `smb ports = 4445`，Samba 就直接监听 4445。端口转发是把外部对 445 的访问重定向到 4445。两者配合使用。

如果不需要 Windows 资源管理器直接访问（使用第三方 SMB 客户端如 RaiDrive），可以不配 iptables，直接连 4445 端口。

## 9. termux-setup-storage 授权弹窗不出现

**症状**：执行 `termux-setup-storage` 后没有弹出授权对话框，`~/storage` 未创建。

**原因**：Android 权限系统未触发授权弹窗，或已被拒绝。

**解决**：在 Android 设置 → 应用 → Termux → 权限 → 存储，手动授予。然后重新执行 `termux-setup-storage`。

但注意：Samba 共享 /sdcard 不依赖 `~/storage`，smbd 以 root 身份（`force user = root`）直接访问 `/sdcard` 原始路径。

> AI生成