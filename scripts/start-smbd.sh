#!/data/data/com.termux/files/usr/bin/bash
#=============================================================
# 启动 Samba 服务（必须在 Termux App 中执行！）
# 用法：bash scripts/start-smbd.sh
#=============================================================
set -euo pipefail

PREFIX=/data/data/com.termux/files/usr

echo "=== 清理旧进程 ==="
pkill -f smbd 2>/dev/null || true
sleep 2

echo "=== 启动 smbd ==="
$PREFIX/bin/smbd -D -s $PREFIX/etc/samba/smb.conf
sleep 3

echo "=== 进程状态 ==="
ps -ef | grep smbd | grep -v grep && echo "smbd 运行中" || echo "错误：smbd 未运行"

echo "=== 端口监听 ==="
# 4445 的十六进制是 0x115D
if cat /proc/net/tcp 2>/dev/null | awk '{print $2}' | grep -qi ":115D"; then
    echo "端口 4445 监听正常"
else
    echo "警告：未检测到 4445 端口监听，请检查日志"
fi

echo "=== tdb 文件属主 ==="
ls -la $PREFIX/var/lib/samba/*.tdb $PREFIX/var/lib/samba/private/*.tdb 2>&1

echo "=== 最新日志 ==="
tail -5 $PREFIX/var/log/samba/log.smbd 2>&1

echo ""
echo "=== 获取手机 IP ==="
ip addr show wlan0 2>/dev/null | grep "inet " || echo "(无法获取 IP，请在手机设置中查看)"

echo ""
echo "=== 启动完成 ==="
echo "在电脑资源管理器中输入：\\手机IP\sdcard 即可访问"
