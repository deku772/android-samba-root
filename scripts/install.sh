#!/data/data/com.termux/files/usr/bin/bash
#=============================================================
# 安装 Samba（在 Termux App 中执行）
# 用法：bash scripts/install.sh
#=============================================================
set -euo pipefail

echo "=== 1/3 更新软件源 ==="
pkg update -y

echo "=== 2/3 安装 samba ==="
pkg install samba -y

echo "=== 3/3 验证版本 ==="
smbd --version
nmbd --version 2>/dev/null || echo "(nmbd 不可用，不影响使用)"

echo ""
echo "=== 安装完成 ==="
echo "下一步：运行 scripts/setup-config.sh 写入配置"
