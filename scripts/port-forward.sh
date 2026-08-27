#!/system/bin/sh
#=============================================================
# 配置 iptables 445→4445 端口转发（在手机 root shell 中执行）
# 用法：su -c "sh /data/local/tmp/port-forward.sh"
#
# 注意：此脚本需要 root 权限，不能在 Termux 中直接运行
# 可通过 ADB 推送后执行：
#   adb push scripts/port-forward.sh /data/local/tmp/
#   adb shell "su -c 'sh /data/local/tmp/port-forward.sh'"
#=============================================================

echo "=== 配置 iptables 445→4445 端口转发 ==="

# OUTPUT 规则：本机发出的 445 请求重定向到 4445
iptables -t nat -A OUTPUT -p tcp --dport 445 -j REDIRECT --to-ports 4445 2>&1
echo "OUTPUT 规则: $?"

# PREROUTING 规则：外部访问 445 的请求重定向到 4445
iptables -t nat -A PREROUTING -p tcp --dport 445 -j REDIRECT --to-ports 4445 2>&1
echo "PREROUTING 规则: $?"

echo ""
echo "=== 当前 NAT 规则 ==="
iptables -t nat -L -n 2>&1 | grep -E "445|4445"

echo ""
echo "=== 局域网 IP ==="
ip addr show wlan0 2>/dev/null | grep "inet " || ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1"

echo ""
echo "=== 完成 ==="
echo "现在 Windows 资源管理器可以直接用 \\手机IP\sdcard 访问"
echo ""
echo "注意：iptables 规则重启后失效，需重新执行此脚本"
