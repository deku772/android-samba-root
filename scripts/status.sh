#!/data/data/com.termux/files/usr/bin/bash
#=============================================================
# 检查 Samba 运行状态（在 Termux App 中执行）
# 用法：bash scripts/status.sh
#=============================================================
set -euo pipefail

PREFIX=/data/data/com.termux/files/usr

echo "=== smbd 进程 ==="
ps -ef | grep smbd | grep -v grep && echo "smbd 运行中" || echo "smbd 未运行"

echo ""
echo "=== 端口 4445 监听 ==="
if cat /proc/net/tcp 2>/dev/null | awk '{print $2}' | grep -qi ":115D"; then
    echo "端口 4445 监听正常"
else
    echo "端口 4445 未监听"
fi

echo ""
echo "=== tdb 文件属主（应为 Termux UID，通常 10475）==="
ls -la $PREFIX/var/lib/samba/*.tdb $PREFIX/var/lib/samba/private/*.tdb 2>&1

echo ""
echo "=== iptables 端口转发规则 ==="
# 需要 root 权限查看 iptables
su -c "iptables -t nat -L -n" 2>/dev/null | grep -E "445|4445" || echo "无法查看 iptables（需 root）或未配置端口转发"

echo ""
echo "=== 手机局域网 IP ==="
ip addr show wlan0 2>/dev/null | grep "inet " || echo "(无法获取 IP)"

echo ""
echo "=== 最近 smbd 日志 ==="
tail -10 $PREFIX/var/log/samba/log.smbd 2>&1 || echo "(无日志文件)"
