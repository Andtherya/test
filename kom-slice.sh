#!/bin/bash

set -e

export AGENT_AUTO_DISCOVERY_KEY="${AGENT_AUTO_DISCOVERY_KEY:-}"
export AGENT_TOKEN="${AGENT_TOKEN:-}"
export AGENT_ENDPOINT="${AGENT_ENDPOINT:-}"
export AGENT_DISABLE_AUTO_UPDATE="${AGENT_DISABLE_AUTO_UPDATE:-true}"

VERSION="1.1.38"
BASE_URL="https://github.com/komari-monitor/komari-agent/releases/download/${VERSION}"

[ -z "${AGENT_TOKEN}" ] && echo "错误: AGENT_TOKEN 未设置" && exit 1

# 获取当前目录
WORKDIR="$(pwd 2>/dev/null)" || {
    echo "错误: 当前目录不可用"
    exit 1
}

[ -z "$WORKDIR" ] && {
    echo "错误: 当前目录不可用"
    exit 1
}

# 检测架构
arch=$(uname -m)
case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "不支持的架构: $arch" && exit 1 ;;
esac

TMP_DIR="$WORKDIR/tmp"
BOT="$TMP_DIR/php"

# 创建临时目录
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 下载
if command -v curl &>/dev/null; then
    curl -fsSL -o "$BOT" "${BASE_URL}/komari-agent-linux-${arch}"
else
    wget -q -O "$BOT" "${BASE_URL}/komari-agent-linux-${arch}"
fi

# 赋予执行权限
chmod +x "$BOT"

# 停止旧进程
pkill -f "$WORKDIR/tmp/php" 2>/dev/null || true
sleep 1

# 后台启动
nohup "$BOT" >/dev/null 2>&1 &
sleep 1
# 删除临时目录
rm -rf "$TMP_DIR"
