#!/data/data/com.termux/files/usr/bin/bash
#=============================================================
# 启动 Samba 服务（必须在 Termux App 中执行！）
# 用法：bash scripts/start-smbd.sh
#
# 重要：smbd 需要补充组才能访问 /sdcard（符号链接 → /storage/self/primary）
#   3003  = inet（网络权限）
#   9997  = everybody（用户空间存储权限）
#   20475 = u0_a475_cache（Termux 缓存组）
#   50475 = u0_a475_ext（Termux 外部存储组）
# 如果通过 su 启动（而非 Termux 内直接执行），必须用 -G 指定补充组
#=============================================================
set -euo pipefail

PREFIX=/data/data/com.termux/files/usr
SMB_CONF=$PREFIX/etc/samba/smb.conf

echo "=== 清理旧进程 ==="
pkill -f smbd 2>/dev/null || true
sleep 2

echo "=== 启动 smbd ==="
# 检查是否在 Termux App 内运行（有补充组）还是通过 su 启动
MY_GROUPS=$(id -G 2>/dev/null)
if echo "$MY_GROUPS" | grep -qw 9997; then
    # 在 Termux App 内运行，补充组已存在
    echo "  运行环境：Termux App（补充组完整）"
    $PREFIX/bin/smbd -D -s $SMB_CONF
else
    # 通过 su 启动，需要手动指定补充组
    echo "  运行环境：su 启动（需要补充组）"
    echo "  使用 su -G 指定补充组：3003 9997 20475 50475"
    su 10475 -G 3003 -G 9997 -G 20475 -G 50475 -c \
        "$PREFIX/bin/smbd -D -s $SMB_CONF"
fi
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
echo "迅雷下载目录：\\手机IP\xunlei（需先执行 mount-xunlei.sh）"
