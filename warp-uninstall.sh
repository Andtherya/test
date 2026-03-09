#!/usr/bin/env bash
# WARP 卸载脚本

set -e

RED='\033[31m'; GREEN='\033[32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }

[ "$(id -u)" != 0 ] && { echo -e "${RED}请使用 root 用户运行${NC}"; exit 1; }

info "停止 WARP..."
wg-quick down warp 2>/dev/null || true
systemctl stop wg-quick@warp 2>/dev/null || true
systemctl disable wg-quick@warp 2>/dev/null || true

info "删除配置文件..."
rm -f /etc/wireguard/warp.conf
rm -f /etc/wireguard/warp-account.conf

info "删除 wireguard-go..."
rm -f /usr/bin/wireguard-go

# 恢复 wg-quick
[ -f /usr/bin/wg-quick.bak ] && mv -f /usr/bin/wg-quick.bak /usr/bin/wg-quick

# Alpine 清理
rm -f /etc/local.d/warp.start 2>/dev/null || true

echo ""
echo -e "${GREEN}WARP 已卸载${NC}"
echo "如需卸载 wireguard-tools:"
echo "  apt remove wireguard-tools  # Debian/Ubuntu"
echo "  yum remove wireguard-tools  # CentOS"
