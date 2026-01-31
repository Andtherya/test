#!/bin/bash

# ============================================
# Komari Agent 安装脚本 (优化版)
# ============================================
# 环境变量:
#   AGENT_TOKEN    - 必需，Agent Token
#   AGENT_DISABLE_AUTO_UPDATE - 可选，禁用自动更新 (默认: true)
#   WORKDIR        - 可选，工作目录 (默认: 当前目录)
#
# 用法:
#   AGENT_TOKEN=xxx ./komari-agent.sh
#   AGENT_TOKEN=xxx AGENT_ENDPOINT=https://your-domain.com ./komari-agent.sh
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
export AGENT_ENDPOINT="${AGENT_ENDPOINT:-https://qykacqzvomax.us-west-1.clawcloudrun.com}"
export AGENT_DISABLE_AUTO_UPDATE="${AGENT_DISABLE_AUTO_UPDATE:-true}"
WORKDIR="${WORKDIR:-$(pwd)}"

# 版本号
VERSION="1.1.38"
BASE_URL="https://github.com/komari-monitor/komari-agent/releases/download/${VERSION}"

# 检查必需参数
if [ -z "${AGENT_TOKEN}" ]; then
    log_error "AGENT_TOKEN 未设置，请设置环境变量后重试"
    echo "用法: AGENT_TOKEN=your_token ./komari-agent.sh"
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

# 检测 init 系统 (先检测 OpenRC，避免误判)
detect_init() {
    if command -v rc-service &>/dev/null; then
        echo "openrc"
    elif command -v systemctl &>/dev/null && [ -d "/etc/systemd/system" ]; then
        echo "systemd"
    elif [ -d "/etc/init.d" ]; then
        echo "sysvinit"
    else
        echo "none"
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

# 安装 systemd 服务
install_systemd() {
    local agent_path="$1"
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
    
    systemctl daemon-reload
    systemctl enable komari-agent
    systemctl restart komari-agent
}

# 安装 OpenRC 服务 (Alpine Linux)
install_openrc() {
    local agent_path="$1"
    log_info "创建 OpenRC 服务..."
    cat >/etc/init.d/komari-agent <<EOF
#!/sbin/openrc-run

name="komari-agent"
description="Komari Agent Service"
command="${agent_path}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/komari-agent.log"
error_log="/var/log/komari-agent.log"
directory="${WORKDIR}"

export AGENT_TOKEN="${AGENT_TOKEN}"
export AGENT_ENDPOINT="${AGENT_ENDPOINT}"
export AGENT_DISABLE_AUTO_UPDATE="${AGENT_DISABLE_AUTO_UPDATE}"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --file --owner root:root --mode 0644 /var/log/komari-agent.log
}
EOF
    chmod +x /etc/init.d/komari-agent
    rc-update add komari-agent default 2>/dev/null || true
    rc-service komari-agent restart
}

# 安装 SysVinit 服务
install_sysvinit() {
    local agent_path="$1"
    log_info "创建 SysVinit 服务..."
    cat >/etc/init.d/komari-agent <<'OUTER'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          komari-agent
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Komari Agent Service
### END INIT INFO

OUTER
    cat >>/etc/init.d/komari-agent <<EOF
AGENT_PATH="${agent_path}"
WORKDIR="${WORKDIR}"
PIDFILE="/var/run/komari-agent.pid"
LOGFILE="/var/log/komari-agent.log"

export AGENT_TOKEN="${AGENT_TOKEN}"
export AGENT_ENDPOINT="${AGENT_ENDPOINT}"
export AGENT_DISABLE_AUTO_UPDATE="${AGENT_DISABLE_AUTO_UPDATE}"

start() {
    if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
        echo "komari-agent is already running"
        return 1
    fi
    echo "Starting komari-agent..."
    cd "\$WORKDIR"
    nohup "\$AGENT_PATH" >>"\$LOGFILE" 2>&1 &
    echo \$! > "\$PIDFILE"
    echo "Started"
}

stop() {
    if [ ! -f "\$PIDFILE" ]; then
        echo "komari-agent is not running"
        return 1
    fi
    echo "Stopping komari-agent..."
    kill \$(cat "\$PIDFILE") 2>/dev/null
    rm -f "\$PIDFILE"
    echo "Stopped"
}

status() {
    if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
        echo "komari-agent is running (PID: \$(cat \$PIDFILE))"
    else
        echo "komari-agent is not running"
    fi
}

case "\$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    *)       echo "Usage: \$0 {start|stop|restart|status}"; exit 1 ;;
esac
EOF
    chmod +x /etc/init.d/komari-agent
    
    # 尝试添加到启动项
    if command -v update-rc.d &>/dev/null; then
        update-rc.d komari-agent defaults
    elif command -v chkconfig &>/dev/null; then
        chkconfig --add komari-agent
        chkconfig komari-agent on
    fi
    
    /etc/init.d/komari-agent restart
}

# 使用 nohup 后台运行 (兜底方案)
install_nohup() {
    local agent_path="$1"
    log_warn "未检测到支持的 init 系统，使用 nohup 后台运行"
    
    # 停止已有进程
    pkill -f "komari-agent" 2>/dev/null || true
    sleep 1
    
    cd "${WORKDIR}"
    export AGENT_TOKEN AGENT_ENDPOINT AGENT_DISABLE_AUTO_UPDATE
    nohup "${agent_path}" >>/var/log/komari-agent.log 2>&1 &
    
    log_info "进程已启动 (PID: $!)"
    log_warn "注意: 系统重启后需要手动启动"
}

# 主逻辑
main() {
    log_info "开始安装 Komari Agent..."
    
    # 检测架构
    local arch=$(detect_arch)
    log_info "检测到系统架构: $arch"
    
    # 检测 init 系统
    local init_system=$(detect_init)
    log_info "检测到 init 系统: $init_system"
    
    # 构建下载 URL
    local download_url="${BASE_URL}/komari-agent-linux-${arch}"
    local agent_path="${WORKDIR}/komari-agent"
    
    # 切换到工作目录
    mkdir -p "${WORKDIR}"
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
    
    # 根据 init 系统安装服务
    case "$init_system" in
        systemd)
            install_systemd "$agent_path"
            ;;
        openrc)
            install_openrc "$agent_path"
            ;;
        sysvinit)
            install_sysvinit "$agent_path"
            ;;
        *)
            install_nohup "$agent_path"
            ;;
    esac
    
    # 检查进程状态
    sleep 2
    if pgrep -f "komari-agent" >/dev/null; then
        log_info "Komari Agent 安装成功并已启动!"
    else
        log_warn "服务可能未正常启动，请检查日志: /var/log/komari-agent.log"
    fi
    
    echo ""
    log_info "配置信息:"
    echo "  - AGENT_TOKEN: ${AGENT_TOKEN:0:8}..."
    echo "  - AGENT_ENDPOINT: ${AGENT_ENDPOINT}"
    echo "  - AGENT_DISABLE_AUTO_UPDATE: ${AGENT_DISABLE_AUTO_UPDATE}"
    echo "  - 架构: ${arch}"
    echo "  - Init 系统: ${init_system}"
    echo "  - 工作目录: ${WORKDIR}"
}

main
