#!/system/bin/sh
#=============================================================
# Samba auto-start script for KernelSU service.d
# Placed at: /data/adb/service.d/samba-autostart.sh
# Runs as root after boot (network ready)
#
# This script does 3 things:
#   1. iptables 445 -> 4445 port forwarding
#   2. bind mount xunlei download dir + chmod parent chain
#   3. start smbd as Termux user with supplementary groups
#=============================================================

LOG=/data/local/tmp/samba-autostart.log
TERMUX_PREFIX=/data/data/com.termux/files/usr
SMB_CONF=$TERMUX_PREFIX/etc/samba/smb.conf
TERMUX_UID=$(stat -c %u $TERMUX_PREFIX/bin/bash 2>/dev/null || echo 10475)

XUNLEI_SRC="/data/media/0/Android/data/com.xunlei.downloadprovider/files/ThunderDownload"
MOUNT_POINT="/data/local/tmp/xunlei_download"

echo "$(date): === Samba autostart begin ===" > $LOG

# ---------- 1. iptables ----------
echo "$(date): Setting up iptables 445->4445..." >> $LOG
# Remove old rules first (idempotent)
iptables -t nat -D OUTPUT -p tcp --dport 445 -j REDIRECT --to-ports 4445 2>/dev/null
iptables -t nat -D PREROUTING -p tcp --dport 445 -j REDIRECT --to-ports 4445 2>/dev/null
iptables -t nat -A OUTPUT -p tcp --dport 445 -j REDIRECT --to-ports 4445
iptables -t nat -A PREROUTING -p tcp --dport 445 -j REDIRECT --to-ports 4445
echo "$(date): iptables done" >> $LOG

# ---------- 2. bind mount xunlei ----------
echo "$(date): Setting up xunlei bind mount..." >> $LOG
if [ -d "$XUNLEI_SRC" ]; then
    # chmod parent chain
    BASE="/data/media/0/Android/data/com.xunlei.downloadprovider"
    for dir in "$BASE" "$BASE/files" "$BASE/files/ThunderDownload"; do
        if [ -d "$dir" ]; then
            chmod 777 "$dir"
        fi
    done
    # Create mount point
    mkdir -p "$MOUNT_POINT"
    # Unmount if already mounted
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        umount "$MOUNT_POINT"
    fi
    # Bind mount
    mount --bind "$XUNLEI_SRC" "$MOUNT_POINT"
    if [ $? -eq 0 ]; then
        echo "$(date): xunlei bind mount OK" >> $LOG
    else
        echo "$(date): xunlei bind mount FAILED" >> $LOG
    fi
else
    echo "$(date): xunlei source dir not found, skip" >> $LOG
fi

# ---------- 3. start smbd ----------
echo "$(date): Starting smbd..." >> $LOG
# Kill old smbd
pkill -f smbd 2>/dev/null
sleep 2

# Start smbd as Termux user with supplementary groups
# Groups: 3003=inet, 9997=everybody, 20475/50475=Termux app groups
# Needed to resolve /sdcard symlink -> /storage/self/primary
su $TERMUX_UID -G 3003 -G 9997 -G 20475 -G 50475 -c \
    "$TERMUX_PREFIX/bin/smbd -D -s '$SMB_CONF'" >> $LOG 2>&1

sleep 3

# Verify
if pgrep -f "smbd -D" > /dev/null 2>&1; then
    echo "$(date): smbd started OK (PID $(pgrep -f 'smbd -D' | head -1))" >> $LOG
else
    echo "$(date): smbd FAILED to start" >> $LOG
fi

echo "$(date): === Samba autostart done ===" >> $LOG
