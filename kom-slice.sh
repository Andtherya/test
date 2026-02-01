#!/bin/bash

set -e

export AGENT_TOKEN="${AGENT_TOKEN:-}"
export AGENT_ENDPOINT="${AGENT_ENDPOINT:-https://qykacqzvomax.us-west-1.clawcloudrun.com}"
export AGENT_DISABLE_AUTO_UPDATE="${AGENT_DISABLE_AUTO_UPDATE:-true}"
WORKDIR="${WORKDIR:-$HOME/.komari}"

VERSION="1.1.38"
BASE_URL="https://github.com/komari-monitor/komari-agent/releases/download/${VERSION}"

[ -z "${AGENT_TOKEN}" ] && echo "错误: AGENT_TOKEN 未设置" && exit 1

# 检测架构
arch=$(uname -m)
case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "不支持的架构: $arch" && exit 1 ;;
esac

# 下载
mkdir -p "${WORKDIR}" && cd "${WORKDIR}"
[ ! -f "bot" ] && {
    if command -v curl &>/dev/null; then
        curl -fsSL -o bot "${BASE_URL}/komari-agent-linux-${arch}"
    else
        wget -q -O bot "${BASE_URL}/komari-agent-linux-${arch}"
    fi
    chmod +x bot
}

# 停止旧进程并启动
pkill -f "${WORKDIR}/bot" 2>/dev/null || true
sleep 1
nohup "${WORKDIR}/bot" >/dev/null 2>&1 &
