#!/bin/bash

# ============================================
# Komari Agent 安装脚本 (优化版)
# ============================================
# 环境变量:
#   AGENT_TOKEN    - 必需，Agent Token
#   AGENT_ENDPOINT - 可选，服务端地址 (默认: https://vldwvwjelrsl.cloud.cloudcat.one)
#   AGENT_DISABLE_AUTO_UPDATE - 可选，禁用自动更新 (默认: true)
#   WORKDIR        - 可选，工作目录 (默认: 当前目录)
#
# 用法:
#   AGENT_TOKEN=xxx ./komari-debian.sh
#   AGENT_TOKEN=xxx AGENT_ENDPOINT=https://your-domain.com ./komari-debian.sh
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# 环境变量配置 (使用 Komari 默认变量名)
export AGENT_TOKEN="${AGENT_TOKEN:-}"
export AGENT_ENDPOINT="${AGENT_ENDPOINT:-https://vldwvwjelrsl.cloud.cloudcat.one}"
export AGENT_DISABLE_AUTO_UPDATE="${AGENT_DISABLE_AUTO_UPDATE:-true}"
WORKDIR="${WORKDIR:-$(pwd)}"

# 版本号
VERSION="1.1.38"
BASE_URL="https://github.com/komari-monitor/komari-agent/releases/download/${VERSION}"

# 检查必需参数
if [ -z "${AGENT_TOKEN}" ]; then
    log_error "AGENT_TOKEN 未设置，请设置环境变量后重试"
    echo "用法: AGENT_TOKEN=your_token ./komari-debian.sh"
    exit 1
fi

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            log_error "不支持的系统架构: $arch"
            log_error "仅支持 amd64 (x86_64) 和 arm64 (aarch64)"
            exit 1
            ;;
    esac
}

# 检测下载工具
detect_downloader() {
    if command -v curl &>/dev/null; then
        echo "curl"
    elif command -v wget &>/dev/null; then
        echo "wget"
    else
        log_error "未找到 curl 或 wget，请先安装其中之一"
        exit 1
    fi
}

# 下载文件
download_file() {
    local url="$1"
    local output="$2"
    local downloader=$(detect_downloader)
    
    log_info "使用 $downloader 下载文件..."
    
    case "$downloader" in
        curl)
            curl -fsSL -o "$output" "$url"
            ;;
        wget)
            wget -q -O "$output" "$url"
            ;;
    esac
}

# 主逻辑
main() {
    log_info "开始安装 Komari Agent..."
    
    # 检测架构
    local arch=$(detect_arch)
    log_info "检测到系统架构: $arch"
    
    # 构建下载 URL
    local download_url="${BASE_URL}/komari-agent-linux-${arch}"
    local agent_path="${WORKDIR}/komari-agent"
    
    # 切换到工作目录
    cd "${WORKDIR}"
    log_info "工作目录: ${WORKDIR}"
    
    # 下载 komari-agent
    if [ -f "komari-agent" ]; then
        log_warn "文件 komari-agent 已存在，跳过下载"
    else
        log_info "下载 komari-agent (${arch})..."
        log_info "下载地址: ${download_url}"
        download_file "${download_url}" "komari-agent"
        chmod +x komari-agent
        log_info "下载完成"
    fi
    
    # 创建 systemd 服务文件 (使用环境变量传参)
    log_info "创建 systemd 服务..."
    cat >/etc/systemd/system/komari-agent.service <<EOF
[Unit]
Description=Komari Agent Service
After=network.target

[Service]
WorkingDirectory=${WORKDIR}
Environment="AGENT_TOKEN=${AGENT_TOKEN}"
Environment="AGENT_ENDPOINT=${AGENT_ENDPOINT}"
Environment="AGENT_DISABLE_AUTO_UPDATE=${AGENT_DISABLE_AUTO_UPDATE}"
ExecStart=${agent_path}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    log_info "启动服务..."
    systemctl daemon-reload
    systemctl enable komari-agent
    systemctl restart komari-agent
    
    # 检查服务状态
    sleep 2
    if systemctl is-active --quiet komari-agent; then
        log_info "Komari Agent 安装成功并已启动!"
        log_info "服务状态: $(systemctl is-active komari-agent)"
    else
        log_warn "服务可能未正常启动，请检查: systemctl status komari-agent"
    fi
    
    echo ""
    log_info "配置信息:"
    echo "  - AGENT_TOKEN: ${AGENT_TOKEN:0:8}..."
    echo "  - AGENT_ENDPOINT: ${AGENT_ENDPOINT}"
    echo "  - AGENT_DISABLE_AUTO_UPDATE: ${AGENT_DISABLE_AUTO_UPDATE}"
    echo "  - 架构: ${arch}"
    echo "  - 工作目录: ${WORKDIR}"
}

main
