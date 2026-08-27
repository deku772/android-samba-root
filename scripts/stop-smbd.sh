#!/data/data/com.termux/files/usr/bin/bash
#=============================================================
# 停止 Samba 服务（在 Termux App 中执行）
# 用法：bash scripts/stop-smbd.sh
#=============================================================
set -euo pipefail

echo "=== 停止 smbd ==="
pkill -f smbd 2>/dev/null && echo "smbd 已停止" || echo "smbd 未在运行"

pkill -f nmbd 2>/dev/null && echo "nmbd 已停止" || true

echo "=== 确认 ==="
ps -ef | grep -E "smbd|nmbd" | grep -v grep && echo "警告：仍有残留进程" || echo "所有 Samba 进程已停止"
