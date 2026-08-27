#!/data/data/com.termux/files/usr/bin/bash
#=============================================================
# Android Samba 一键配置脚本
# 在 Termux App 中执行
#
# 用法：
#   bash setup.sh              # 交互式模式（逐步确认）
#   bash setup.sh --auto       # 全自动模式（跳过所有确认）
#   bash setup.sh --status     # 仅查看状态
#   bash setup.sh --stop       # 停止服务
#   bash setup.sh --help       # 显示帮助
#=============================================================
set -euo pipefail

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PREFIX=/data/data/com.termux/files/usr
CONF=$PREFIX/etc/samba/smb.conf
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTO=0

# ---------- 辅助函数 ----------
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

confirm() {
    if [ "$AUTO" -eq 1 ]; then
        return 0
    fi
    local q="$1"
    echo -n -e "${YELLOW}${q} [Y/n] ${NC}"
    read -r ans
    case "$ans" in
        n|N|no|NO) return 1 ;;
        *) return 0 ;;
    esac
}

header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

# ---------- 步骤函数 ----------
step1_install() {
    header "步骤 1/6：安装 Samba"
    if command -v smbd &>/dev/null; then
        local v
        v=$(smbd --version 2>/dev/null | head -1)
        ok "Samba 已安装：$v"
        if ! confirm "是否重新安装/更新？"; then
            return 0
        fi
    fi
    info "更新软件源..."
    pkg update -y
    info "安装 samba..."
    pkg install samba -y
    ok "Samba 安装完成：$(smbd --version 2>/dev/null | head -1)"
}

step2_config() {
    header "步骤 2/6：写入 Samba 配置"
    local conf_src="$SCRIPT_DIR/config/smb-anonymous.conf"
    if [ ! -f "$conf_src" ]; then
        conf_src="$SCRIPT_DIR/../config/smb-anonymous.conf"
    fi
    if [ ! -f "$conf_src" ]; then
        fail "找不到配置模板 config/smb-anonymous.conf"
        fail "请确保仓库完整，或将配置手动放到 $CONF"
        return 1
    fi

    if [ -f "$CONF" ]; then
        cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
        ok "已备份原配置"
    fi
    cp "$conf_src" "$CONF"
    ok "配置已写入 $CONF"

    info "验证配置语法..."
    if testparm -s "$CONF" 2>&1 | grep -qi "ERROR"; then
        warn "testparm 报告语法错误，请检查配置文件"
        testparm -s "$CONF" 2>&1 | tail -20
    else
        ok "配置语法验证通过"
    fi
}

step3_fix_tdb() {
    header "步骤 3/6：修复 tdb 权限"
    info "删除 root 属主的 tdb 文件（smbd 首次启动时自动重建）..."
    local tdb_dir=$PREFIX/var/lib/samba
    local tdb_priv=$PREFIX/var/lib/samba/private
    local cleaned=0

    for f in account_policy.tdb group_mapping.tdb; do
        if [ -f "$tdb_dir/$f" ]; then
            local owner
            owner=$(stat -c %u "$tdb_dir/$f" 2>/dev/null || echo "?")
            if [ "$owner" != "$(id -u)" ]; then
                rm -f "$tdb_dir/$f" 2>/dev/null && ok "  已删除 $f（原属主 UID=$owner）" && cleaned=1
            else
                ok "  $f 属主正确，跳过"
            fi
        fi
    done

    for f in passdb.tdb secrets.tdb; do
        if [ -f "$tdb_priv/$f" ]; then
            local owner
            owner=$(stat -c %u "$tdb_priv/$f" 2>/dev/null || echo "?")
            if [ "$owner" != "$(id -u)" ]; then
                rm -f "$tdb_priv/$f" 2>/dev/null && ok "  已删除 $f（原属主 UID=$owner）" && cleaned=1
            else
                ok "  $f 属主正确，跳过"
            fi
        fi
    done

    [ "$cleaned" -eq 0 ] && ok "所有 tdb 文件属主正确，无需清理"
}

step4_iptables() {
    header "步骤 4/6：配置 iptables 端口转发"
    info "需要 root 权限将 445 端口转发到 4445"
    if ! su -c "true" 2>/dev/null; then
        warn "无法获取 root 权限，跳过端口转发"
        warn "Windows 资源管理器无法直接用 \\IP\\sdcard 访问"
        warn "替代方案：用 RaiDrive 等 SMB 客户端连接 4445 端口"
        return 0
    fi

    # 检查是否已存在规则
    if su -c "iptables -t nat -L OUTPUT -n" 2>/dev/null | grep -q "dpt:445"; then
        ok "端口转发规则已存在，跳过"
    else
        su -c "iptables -t nat -A OUTPUT -p tcp --dport 445 -j REDIRECT --to-ports 4445"
        su -c "iptables -t nat -A PREROUTING -p tcp --dport 445 -j REDIRECT --to-ports 4445"
        ok "iptables 规则已添加（445 → 4445）"
    fi
    warn "iptables 规则重启后失效，需重新执行此脚本"
}

step5_start() {
    header "步骤 5/6：启动 Samba 服务"

    info "清理旧进程..."
    pkill -f smbd 2>/dev/null || true
    sleep 2

    info "启动 smbd..."
    # 检查当前进程是否有补充组（9997=everybody）
    # /sdcard 是符号链接 → /storage/self/primary，需要 everybody 组才能穿越
    if id -G 2>/dev/null | tr ' ' '\n' | grep -qw 9997; then
        ok "补充组完整，直接启动"
        $PREFIX/bin/smbd -D -s "$CONF" 2>&1
    else
        warn "当前缺少补充组，尝试通过 su 指定补充组启动..."
        su $(id -u) -G 3003 -G 9997 -G 20475 -G 50475 -c \
            "$PREFIX/bin/smbd -D -s '$CONF'" 2>&1
    fi
    sleep 3

    # 验证
    if ps -ef | grep smbd | grep -v grep | head -1; then
        ok "smbd 进程运行中"
    else
        fail "smbd 未运行！日志："
        tail -20 "$PREFIX/var/log/samba/log.smbd" 2>/dev/null
        fail "请查看 docs/troubleshooting.md 排查问题"
        return 1
    fi

    if cat /proc/net/tcp 2>/dev/null | awk '{print $2}' | grep -qi ":115D"; then
        ok "端口 4445 监听正常"
    else
        warn "未检测到 4445 端口监听"
    fi

    local ip
    ip=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$ip" ]; then
        ok "手机 IP: $ip"
    else
        ip=$(ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)
        if [ -n "$ip" ]; then
            ok "手机 IP: $ip"
        else
            warn "无法自动获取 IP，请在手机设置中查看"
            ip="<手机IP>"
        fi
    fi

    # 最终汇总
    header "配置完成！"
    echo -e "  ${GREEN}Windows 资源管理器地址栏输入：${NC}"
    echo ""
    echo -e "           ${BLUE}\\\\${ip}\sdcard${NC}  — 内置存储"
    echo -e "           ${BLUE}\\\\${ip}\xunlei${NC}  — 迅雷下载（需先执行 mount-xunlei.sh）"
    echo ""
    echo -e "  ${GREEN}或映射网络驱动器：${NC} net use Z: \\\\${ip}\sdcard"
    echo ""
    warn "安全提醒：匿名共享整个 /sdcard，同一 WiFi 下所有设备均可访问"
    warn "用完后可停止服务：bash setup.sh --stop"
    echo ""
}

show_status() {
    header "Samba 运行状态"

    echo -e "${BLUE}1. smbd 进程${NC}"
    local smbd_pid
    smbd_pid=$(ps -ef | grep smbd | grep -v grep | head -1 | awk '{print $2}')
    if [ -n "$smbd_pid" ]; then
        local groups
        groups=$(cat /proc/$smbd_pid/status 2>/dev/null | grep "^Groups:" | sed 's/Groups://')
        if echo "$groups" | grep -qw 9997; then
            ok "smbd 运行中（PID $smbd_pid，补充组完整）"
        else
            warn "smbd 运行中（PID $smbd_pid）但缺少补充组，/sdcard 可能无法访问"
        fi
    else
        fail "smbd 未运行"
    fi

    echo ""
    echo -e "${BLUE}2. 端口 4445${NC}"
    if cat /proc/net/tcp 2>/dev/null | awk '{print $2}' | grep -qi ":115D"; then
        ok "端口 4445 监听正常"
    else
        fail "端口 4445 未监听"
    fi

    echo ""
    echo -e "${BLUE}3. iptables 端口转发${NC}"
    if su -c "iptables -t nat -L -n" 2>/dev/null | grep -q "dpt:445"; then
        ok "iptables 445→4445 转发规则已配置"
    else
        fail "iptables 端口转发未配置"
    fi

    echo ""
    echo -e "${BLUE}4. tdb 文件属主${NC}"
    ls -la $PREFIX/var/lib/samba/*.tdb $PREFIX/var/lib/samba/private/*.tdb 2>&1 | head -10

    echo ""
    echo -e "${BLUE}5. 手机 IP${NC}"
    local ip
    ip=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}')
    if [ -n "$ip" ]; then
        ok "IP: $ip"
    else
        warn "无法获取 IP"
    fi

    echo ""
    echo -e "${BLUE}6. 迅雷下载共享${NC}"
    if mountpoint -q /data/local/tmp/xunlei_download 2>/dev/null; then
        ok "迅雷目录已挂载到 /data/local/tmp/xunlei_download"
    else
        warn "迅雷目录未挂载，执行 mount-xunlei.sh 启用"
    fi

    echo ""
    echo -e "${BLUE}7. 最近日志${NC}"
    tail -10 "$PREFIX/var/log/samba/log.smbd" 2>/dev/null || echo "(无日志)"
}

stop_service() {
    header "停止 Samba 服务"
    pkill -f smbd 2>/dev/null && ok "smbd 已停止" || info "smbd 未在运行"
    pkill -f nmbd 2>/dev/null && ok "nmbd 已停止" || true
    ps -ef | grep -E "smbd|nmbd" | grep -v grep && warn "仍有残留进程" || ok "所有 Samba 进程已停止"
    # 卸载迅雷 bind mount
    if mountpoint -q /data/local/tmp/xunlei_download 2>/dev/null; then
        su -c "umount /data/local/tmp/xunlei_download" 2>/dev/null && ok "已卸载迅雷目录挂载" || true
    fi
}

show_help() {
    cat <<'EOF'
Android Samba 一键配置脚本
在 Termux App 中执行

用法：
  bash setup.sh              交互式配置（逐步确认）
  bash setup.sh --auto       全自动配置（跳过所有确认）
  bash setup.sh --status     查看运行状态
  bash setup.sh --stop       停止 Samba 服务
  bash setup.sh --xunlei     挂载迅雷下载目录
  bash setup.sh --help       显示此帮助

流程（6 步）：
  1. 安装 Samba（pkg install samba）
  2. 写入匿名共享配置（/sdcard + 迅雷下载目录）
  3. 修复 tdb 文件权限
  4. 配置 iptables 445→4445 端口转发（需 root）
  5. 启动 smbd 并验证
  6. 可选：挂载迅雷下载目录（需 root）

注意：
  - smbd 需要补充组 3003,9997,20475,50475 才能访问 /sdcard
  - iptables 规则重启后失效，需重新运行
  - bind mount 重启后失效，迅雷共享需重新执行 --xunlei
  - 匿名共享整个 /sdcard，请确保在可信局域网使用
EOF
}

step6_xunlei() {
    header "步骤 6/6：挂载迅雷下载目录（可选）"

    local mount_script="$SCRIPT_DIR/scripts/mount-xunlei.sh"
    if [ ! -f "$mount_script" ]; then
        mount_script="$SCRIPT_DIR/mount-xunlei.sh"
    fi
    if [ ! -f "$mount_script" ]; then
        warn "找不到 mount-xunlei.sh，跳过迅雷共享"
        warn "如需迅雷共享，请手动执行 scripts/mount-xunlei.sh"
        return 0
    fi

    if ! confirm "是否挂载迅雷下载目录？"; then
        info "跳过迅雷共享配置（可稍后手动执行 mount-xunlei.sh）"
        return 0
    fi

    info "执行挂载脚本（需要 root）..."
    su -c "sh $mount_script"

    if mountpoint -q /data/local/tmp/xunlei_download 2>/dev/null; then
        ok "迅雷下载目录已挂载"
        echo ""
        echo -e "  ${GREEN}迅雷共享地址：${NC} \\手机IP\xunlei"
        echo ""
        warn "bind mount 重启后失效，需重新执行 mount-xunlei.sh"
    else
        warn "挂载失败，请检查迅雷是否已安装且有下载记录"
    fi
}

# ---------- 主入口 ----------
main() {
    local mode="${1:-}"

    case "$mode" in
        --auto)   AUTO=1 ;;
        --status) show_status; exit 0 ;;
        --stop)   stop_service; exit 0 ;;
        --xunlei) step6_xunlei; exit 0 ;;
        --help|-h) show_help; exit 0 ;;
        "")       ;;
        *)        warn "未知参数: $mode"; show_help; exit 1 ;;
    esac

    header "Android Samba 一键配置"
    echo "  模式：$([ "$AUTO" -eq 1 ] && echo "全自动" || echo "交互式")"
    echo "  设备：$(getprop ro.product.model 2>/dev/null || echo "Unknown")"
    echo "  Android：$(getprop ro.build.version.release 2>/dev/null || echo "?")"
    echo "  Root：$([ "$(id -u)" = "0" ] && echo "当前是 root（不推荐直接用 root 运行）" || echo "非 root 用户（正常）")"
    echo ""

    if [ "$(id -u)" = "0" ]; then
        fail "请勿以 root 身份运行此脚本！"
        fail "请在 Termux App 中以普通用户身份执行"
        exit 1
    fi

    confirm "开始配置 Android Samba 共享？" || exit 0

    step1_install
    step2_config
    step3_fix_tdb
    step4_iptables
    step5_start
    step6_xunlei
}

main "$@"
