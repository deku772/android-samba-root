#!/system/bin/sh
#=============================================================
# 挂载迅雷下载目录到 Samba 可访问路径（在手机 root shell 中执行）
#
# 原理：Android 11+ Scoped Storage 限制 smbd（untrusted_app_27 上下文）
# 访问其他应用的 Android/data 目录。直接 bind mount 到 /sdcard 下
# 也会被 sdcardfs 的 mask=6 限制为 drwxrwx--x，其他用户无法列出。
#
# 解决方案：bind mount 到 /data/local/tmp/xunlei_download（ext4 层），
# 并修复整个父目录链的 ext4 权限为 777，smbd 即可正常访问。
#
# 用法：
#   adb push scripts/mount-xunlei.sh /sdcard/
#   adb shell "su -c 'sh /sdcard/mount-xunlei.sh'"
#
# 注意：bind mount 重启后失效，需重新执行此脚本
#=============================================================

# ext4 层真实路径（绕过 FUSE/sdcardfs 限制）
XUNLEI_SRC="/data/media/0/Android/data/com.xunlei.downloadprovider/files/ThunderDownload"
MOUNT_POINT="/data/local/tmp/xunlei_download"

echo "=== 挂载迅雷下载目录 ==="

# 检查源目录是否存在
if [ ! -d "$XUNLEI_SRC" ]; then
    echo "错误：迅雷下载目录不存在：$XUNLEI_SRC"
    echo "请确认迅雷已安装且有过下载记录"
    exit 1
fi

# 修复 ext4 层父目录链权限（smbd 需要穿越每一级父目录）
echo "=== 修复父目录链权限 ==="
BASE="/data/media/0/Android/data/com.xunlei.downloadprovider"
for dir in "$BASE" "$BASE/files" "$BASE/files/ThunderDownload"; do
    if [ -d "$dir" ]; then
        chmod 777 "$dir"
        echo "  chmod 777 $dir"
    fi
done

# 创建挂载点
mkdir -p "$MOUNT_POINT"

# 如果已经挂载了，先卸载
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "已存在挂载，先卸载..."
    umount "$MOUNT_POINT"
fi

# 执行 bind mount（ext4 层 → ext4 层，不经过 sdcardfs）
mount --bind "$XUNLEI_SRC" "$MOUNT_POINT"

if [ $? -eq 0 ]; then
    echo "挂载成功：$XUNLEI_SRC → $MOUNT_POINT"
    echo ""
    echo "目录内容："
    ls -la "$MOUNT_POINT" | head -10
    echo ""
    echo "现在可以通过 \\\\手机IP\\xunlei 访问迅雷下载目录"
    echo "重启 smbd 后生效（在 Termux 中执行：pkill smbd; sleep 2; smbd -D）"
else
    echo "错误：挂载失败"
    exit 1
fi
