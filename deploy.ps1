#=============================================================
# deploy.ps1 — 电脑端一键部署脚本
# 通过 ADB 将仓库推送到手机并触发 Samba 配置
#
# 用法：
#   .\deploy.ps1                 # 交互式部署
#   .\deploy.ps1 -Auto           # 全自动部署
#   .\deploy.ps1 -Status         # 查看手机端运行状态
#   .\deploy.ps1 -Stop           # 停止手机端 Samba
#   .\deploy.ps1 -Test           # 从电脑端测试连接
#
# 前提：
#   - 手机已开启 USB 调试并连接电脑
#   - 电脑已安装 ADB（platform-tools）
#   - 手机已 root（Magisk/KernelSU）
#   - 手机已安装 Termux
#=============================================================
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$Status,
    [switch]$Stop,
    [switch]$Test
)

$ErrorActionPreference = "Stop"

# ---------- 颜色 ----------
function Write-Info  { param([string]$Msg) Write-Host "[INFO]  $Msg" -ForegroundColor Blue }
function Write-Ok    { param([string]$Msg) Write-Host "[OK]    $Msg" -ForegroundColor Green }
function Write-Warn2 { param([string]$Msg) Write-Host "[WARN]  $Msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "[FAIL]  $Msg" -ForegroundColor Red }

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 57) -ForegroundColor Blue
    Write-Host "  $Title" -ForegroundColor Blue
    Write-Host ("=" * 57) -ForegroundColor Blue
}

# ---------- ADB 检查 ----------
function Test-ADB {
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adb) {
        Write-Fail "未找到 ADB，请先安装 Android Platform-Tools"
        Write-Info "下载地址：https://developer.android.com/tools/releases/platform-tools"
        exit 1
    }
    $devices = & adb devices 2>&1
    $lines = ($devices -split "`n" | Where-Object { $_ -match "\tdevice$" })
    if ($lines.Count -eq 0) {
        Write-Fail "未检测到已连接的设备"
        Write-Info "请确保：1) 手机已开启 USB 调试  2) 已用数据线连接  3) 已授权此电脑"
        exit 1
    }
    if ($lines.Count -gt 1) {
        Write-Warn2 "检测到多个设备，将使用第一个"
    }
    $devId = ($lines[0] -split "`t")[0]
    Write-Ok "已连接设备：$devId"
    return $devId
}

# ---------- Root 检查 ----------
function Test-Root {
    $result = & adb shell "su -c 'id'" 2>&1
    if ($LASTEXITCODE -eq 0 -and $result -match "uid=0") {
        Write-Ok "手机已 root"
        return $true
    } else {
        Write-Fail "手机未 root 或未授权 su 权限"
        Write-Info "此方案需要 root（Magisk / KernelSU 等）"
        return $false
    }
}

# ---------- Termux 检查 ----------
function Test-Termux {
    $result = & adb shell "su -c 'ls /data/data/com.termux/files/usr/bin/bash 2>/dev/null && echo EXISTS'" 2>&1
    if ($result -match "EXISTS") {
        Write-Ok "Termux 已安装"
        return $true
    } else {
        Write-Fail "未检测到 Termux"
        Write-Info "请先在手机上安装 Termux（推荐 F-Droid 版）"
        Write-Info "https://f-droid.org/packages/com.termux/"
        return $false
    }
}

# ---------- 获取手机 IP ----------
function Get-PhoneIP {
    $ip = & adb shell "ip addr show wlan0 2>/dev/null | grep 'inet '" 2>&1
    $ip = ($ip -split "\s+")[2]
    if ($ip -match "^\d+\.\d+\.\d+\.\d+") {
        $ip = $ip.Split("/")[0]
        return $ip
    }
    return $null
}

# ---------- 推送仓库 ----------
function Push-Repo {
    Write-Info "推送仓库文件到手机..."
    $repoDir = $PSScriptRoot
    $remoteDir = "/data/local/tmp/android-samba-root"

    # 清理旧的
    & adb shell "rm -rf $remoteDir" 2>&1 | Out-Null
    & adb shell "mkdir -p $remoteDir/config $remoteDir/scripts" 2>&1 | Out-Null

    # 推送文件
    & adb push "$repoDir\setup.sh" "$remoteDir/" 2>&1 | ForEach-Object {
        if ($_ -match "pushed") { Write-Ok "  setup.sh" }
    }
    & adb push "$repoDir\config\smb-anonymous.conf" "$remoteDir/config/" 2>&1 | ForEach-Object {
        if ($_ -match "pushed") { Write-Ok "  config/smb-anonymous.conf" }
    }
    & adb push "$repoDir\scripts\install.sh" "$remoteDir/scripts/" 2>&1 | Out-Null
    & adb push "$repoDir\scripts\setup-config.sh" "$remoteDir/scripts/" 2>&1 | Out-Null
    & adb push "$repoDir\scripts\start-smbd.sh" "$remoteDir/scripts/" 2>&1 | Out-Null
    & adb push "$repoDir\scripts\stop-smbd.sh" "$remoteDir/scripts/" 2>&1 | Out-Null
    & adb push "$repoDir\scripts\port-forward.sh" "$remoteDir/scripts/" 2>&1 | Out-Null
    & adb push "$repoDir\scripts\status.sh" "$remoteDir/scripts/" 2>&1 | Out-Null
    & adb push "$repoDir\scripts\mount-xunlei.sh" "$remoteDir/scripts/" 2>&1 | Out-Null
    Write-Ok "所有脚本已推送到 $remoteDir"
}

# ---------- 通过 Termux 执行命令 ----------
function Invoke-Termux {
    param([string]$Command)

    # Termux 的 UID 通常是 10475，但需要动态获取
    $termuxUid = & adb shell "su -c 'stat -c %u /data/data/com.termux/files/usr/bin/bash'" 2>&1
    $termuxUid = $termuxUid.Trim()

    if (-not $termuxUid -match "^\d+$") {
        Write-Warn2 "无法获取 Termux UID，使用默认值 10475"
        $termuxUid = "10475"
    }

    # 通过 su 切换到 Termux 用户执行，设置完整环境变量
    $envSetup = "export HOME=/data/data/com.termux/files/home; export PREFIX=/data/data/com.termux/files/usr; export PATH=`$PREFIX/bin:`$PREFIX/bin/applets:/system/bin:/system/xbin; export LD_LIBRARY_PATH=`$PREFIX/lib; export TMPDIR=`$PREFIX/tmp; export TERM=xterm-256color; export TERMINFO=`$PREFIX/share/terminfo; export ANDROID_ROOT=/system; export ANDROID_DATA=/data; cd `$HOME"

    $fullCmd = "su $termuxUid -c '$envSetup; $Command'"
    $result = & adb shell $fullCmd 2>&1
    return $result
}

# ---------- 主流程 ----------
$devId = Test-ADB

# --Test 模式：从电脑测试连接
if ($Test) {
    Write-Header "测试 SMB 连接"
    $ip = Get-PhoneIP
    if (-not $ip) { Write-Fail "无法获取手机 IP"; exit 1 }
    Write-Info "手机 IP: $ip"

    Write-Info "测试端口 445..."
    $r445 = Test-NetConnection -ComputerName $ip -Port 445 -WarningAction SilentlyContinue
    if ($r445.TcpTestSucceeded) { Write-Ok "端口 445 可达" } else { Write-Fail "端口 445 不可达" }

    Write-Info "测试端口 4445..."
    $r4445 = Test-NetConnection -ComputerName $ip -Port 4445 -WarningAction SilentlyContinue
    if ($r4445.TcpTestSucceeded) { Write-Ok "端口 4445 可达" } else { Write-Fail "端口 4445 不可达" }

    if ($r445.TcpTestSucceeded) {
        Write-Info "尝试 dir \\$ip\sdcard..."
        $dirResult = cmd /c "dir \\$ip\sdcard 2>&1" | Select-Object -First 15
        if ($dirResult -match "个文件|File\(s\)") {
            Write-Ok "SMB 共享访问成功！"
            $dirResult | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Warn2 "SMB 访问返回异常（可能需要先 net use 挂载）"
            Write-Info "手动尝试：net use \\$ip\sdcard /user:guest"
        }
    }
    exit 0
}

# --Status 模式
if ($Status) {
    Write-Header "查看手机端 Samba 状态"
    $result = Invoke-Termux -Command "bash /data/local/tmp/android-samba-root/scripts/status.sh"
    Write-Host $result
    exit 0
}

# --Stop 模式
if ($Stop) {
    Write-Header "停止手机端 Samba"
    $result = Invoke-Termux -Command "bash /data/local/tmp/android-samba-root/scripts/stop-smbd.sh"
    Write-Host $result
    exit 0
}

# ---------- 正常部署流程 ----------
Write-Header "Android Samba 一键部署"
Write-Host "  模式：$(if ($Auto) { '全自动' } else { '交互式' })"
Write-Host "  电脑：$(hostname)"
Write-Host "  时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

# 前置检查
Write-Header "前置检查"
Test-Root | Out-Null
Test-Termux | Out-Null

$ip = Get-PhoneIP
if ($ip) { Write-Ok "手机 IP: $ip" } else { Write-Warn2 "无法获取手机 IP（稍后在手机上查看）" }

# 确认
if (-not $Auto) {
    $confirm = Read-Host "开始部署？（Y/n）"
    if ($confirm -match "^[nN]") { Write-Info "已取消"; exit 0 }
}

# 步骤 1-3：推送 + 安装 + 配置 + 修复 tdb
Write-Header "步骤 1/4：推送文件到手机"
Push-Repo

Write-Header "步骤 2/4：安装 Samba + 写入配置 + 修复 tdb"
Write-Info "在 Termux 环境中执行..."
$result = Invoke-Termux -Command "bash /data/local/tmp/android-samba-root/scripts/install.sh && bash /data/local/tmp/android-samba-root/scripts/setup-config.sh"
Write-Host $result

# 步骤 3：iptables 端口转发（root 执行）
Write-Header "步骤 3/4：配置 iptables 端口转发"
Write-Info "以 root 权限执行..."
$fwResult = & adb shell "su -c 'sh /data/local/tmp/android-samba-root/scripts/port-forward.sh'" 2>&1
Write-Host $fwResult

# 步骤 4：提示用户在 Termux App 中手动启动
Write-Header "步骤 4/4：启动 Samba"
Write-Warn2 "重要：smbd 必须在 Termux App 中手动启动！"
Write-Warn2 "ADB/su 启动的进程 SELinux 上下文不正确，无法访问 /sdcard"
Write-Host ""
Write-Info "请在手机上操作："
Write-Host "  1. 打开 Termux App" -ForegroundColor White
Write-Host "  2. 执行以下命令：" -ForegroundColor White
Write-Host ""
    Write-Host "     bash /data/local/tmp/android-samba-root/scripts/start-smbd.sh" -ForegroundColor Cyan
    Write-Host ""
Write-Host "  3. 或运行一键脚本：" -ForegroundColor White
Write-Host ""
    Write-Host "     bash /data/local/tmp/android-samba-root/setup.sh --auto" -ForegroundColor Cyan
    Write-Host ""

# 等待用户启动后测试
if (-not $Auto) {
    $confirm = Read-Host "已在 Termux 中启动 smbd 了吗？（回车继续测试 / n 跳过）"
    if ($confirm -match "^[nN]") { Write-Info "跳过测试"; exit 0 }
}

# 测试连接
Write-Header "验证连接"
$ip = Get-PhoneIP
if (-not $ip) { Write-Warn2 "无法获取 IP"; exit 0 }

Write-Info "测试端口 445..."
$r = Test-NetConnection -ComputerName $ip -Port 445 -WarningAction SilentlyContinue
if ($r.TcpTestSucceeded) {
    Write-Ok "端口 445 可达"
} else {
    Write-Fail "端口 445 不可达，smbd 可能未启动"
    exit 1
}

Write-Info "测试 SMB 共享访问..."
$testDir = cmd /c "dir \\$ip\sdcard 2>&1" | Select-Object -First 10
if ($testDir -match "个目录|Dir\(s\)") {
    Write-Ok "SMB 共享访问成功！"
    Write-Host ""
    Write-Header "部署完成！"
    Write-Host "  资源管理器地址：\\$ip\sdcard" -ForegroundColor Green
    Write-Host "  映射网络驱动器：net use Z: \\$ip\sdcard" -ForegroundColor Green
    Write-Host ""
    Write-Info "如需用主机名访问（\\k20p\sdcard），请运行："
    Write-Host "  .\update-hosts.ps1" -ForegroundColor Cyan
} else {
    Write-Warn2 "自动测试未通过，请确认 smbd 已在 Termux 中启动"
    Write-Info "手动测试：dir \\$ip\sdcard"
}
