#!/data/data/com.termux/files/usr/bin/bash
#=============================================================
# 写入 Samba 配置并修复 tdb 权限（在 Termux App 中执行）
# 用法：bash scripts/setup-config.sh
#=============================================================
set -euo pipefail

PREFIX=/data/data/com.termux/files/usr
CONF=$PREFIX/etc/samba/smb.conf
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== 1/4 备份原配置 ==="
if [ -f "$CONF" ]; then
    cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
    echo "已备份原配置"
else
    echo "无原配置，跳过备份"
fi

echo "=== 2/4 写入新配置 ==="
if [ -f "$SCRIPT_DIR/../config/smb-anonymous.conf" ]; then
    cp "$SCRIPT_DIR/../config/smb-anonymous.conf" "$CONF"
    echo "已从仓库复制配置"
else
    echo "错误：找不到 config/smb-anonymous.conf"
    echo "请确保仓库完整，或手动复制配置文件到 $CONF"
    exit 1
fi

echo "=== 3/4 验证配置语法 ==="
testparm -s "$CONF" 2>&1 | head -60

echo "=== 4/4 修复 tdb 权限 ==="
echo "删除 root 属主的 tdb 文件（smbd 首次启动时自动重建）..."
rm -f $PREFIX/var/lib/samba/account_policy.tdb 2>/dev/null && echo "  已删除 account_policy.tdb"
rm -f $PREFIX/var/lib/samba/group_mapping.tdb 2>/dev/null && echo "  已删除 group_mapping.tdb"
rm -f $PREFIX/var/lib/samba/private/passdb.tdb 2>/dev/null && echo "  已删除 passdb.tdb"
rm -f $PREFIX/var/lib/samba/private/secrets.tdb 2>/dev/null && echo "  已删除 secrets.tdb"

echo ""
echo "=== 配置完成 ==="
echo "下一步："
echo "  1. 在手机 root shell 中执行 scripts/port-forward.sh 配置端口转发"
echo "  2. 在 Termux App 中执行 scripts/start-smbd.sh 启动服务"
