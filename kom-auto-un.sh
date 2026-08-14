#!/bin/bash

# ============================================================
# Komari Agent 卸载脚本
# ============================================================

set -u

# ============================================================
# 颜色
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================================
# 日志
# ============================================================

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# ============================================================
# Root 检查
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 权限运行此脚本"
    echo "例如：sudo bash $0"
    exit 1
fi

# ============================================================
# 全局变量
# ============================================================

AGENT_PID=""
AGENT_PATH=""
WORKDIR=""

# ============================================================
# 自动检测 Agent 路径
# ============================================================

detect_agent() {

    # --------------------------------------------------------
    # 1. 从正在运行的进程获取
    # --------------------------------------------------------

    local pid
    pid="$(pgrep -xo komari-agent 2>/dev/null || true)"

    if [ -n "$pid" ] && [ -e "/proc/$pid/exe" ]; then

        local path
        path="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"

        if [ -n "$path" ] && [ -f "$path" ]; then
            AGENT_PID="$pid"
            AGENT_PATH="$path"
            WORKDIR="$(dirname "$path")"

            info "通过运行中的进程找到 Agent"
            info "PID:     $AGENT_PID"
            info "Agent:   $AGENT_PATH"
            info "目录:    $WORKDIR"

            return 0
        fi
    fi

    # --------------------------------------------------------
    # 2. 从 systemd 获取
    # --------------------------------------------------------

    if command -v systemctl >/dev/null 2>&1; then

        local service_file=""

        for file in \
            /etc/systemd/system/komari-agent.service \
            /usr/lib/systemd/system/komari-agent.service \
            /lib/systemd/system/komari-agent.service
        do
            if [ -f "$file" ]; then
                service_file="$file"
                break
            fi
        done

        if [ -n "$service_file" ]; then

            local path
            path="$(
                grep -oE '/[^[:space:]"]*komari-agent' \
                    "$service_file" 2>/dev/null |
                head -n 1
            )"

            if [ -n "$path" ] && [ -f "$path" ]; then
                AGENT_PATH="$(readlink -f "$path")"
                WORKDIR="$(dirname "$AGENT_PATH")"

                info "通过 systemd 找到 Agent"
                info "Agent: $AGENT_PATH"
                info "目录:  $WORKDIR"

                return 0
            fi
        fi
    fi

    # --------------------------------------------------------
    # 3. 从 init 脚本获取
    # --------------------------------------------------------

    local init_file="/etc/init.d/komari-agent"

    if [ -f "$init_file" ]; then

        local path
        path="$(
            grep -oE '/[^[:space:]"]*komari-agent' \
                "$init_file" 2>/dev/null |
            head -n 1
        )"

        if [ -n "$path" ] && [ -f "$path" ]; then
            AGENT_PATH="$(readlink -f "$path")"
            WORKDIR="$(dirname "$AGENT_PATH")"

            info "通过 init 脚本找到 Agent"
            info "Agent: $AGENT_PATH"
            info "目录:  $WORKDIR"

            return 0
        fi
    fi

    warn "无法自动找到 Komari Agent"
    return 1
}

# ============================================================
# 停止 systemd 服务
# ============================================================

remove_systemd() {

    if ! command -v systemctl >/dev/null 2>&1; then
        return
    fi

    if systemctl list-unit-files 2>/dev/null |
        grep -q '^komari-agent.service'
    then
        info "停止 systemd 服务..."

        systemctl stop komari-agent 2>/dev/null || true
        systemctl disable komari-agent 2>/dev/null || true
    fi

    for file in \
        /etc/systemd/system/komari-agent.service \
        /usr/lib/systemd/system/komari-agent.service \
        /lib/systemd/system/komari-agent.service
    do
        if [ -f "$file" ]; then
            info "删除: $file"
            rm -f "$file"
        fi
    done

    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed komari-agent 2>/dev/null || true
}

# ============================================================
# 停止 OpenRC / SysVinit
# ============================================================

remove_init() {

    local init_file="/etc/init.d/komari-agent"

    if [ ! -f "$init_file" ]; then
        return
    fi

    info "停止 init 服务..."

    if command -v rc-service >/dev/null 2>&1; then
        rc-service komari-agent stop 2>/dev/null || true
        rc-update del komari-agent default 2>/dev/null || true
    fi

    if command -v service >/dev/null 2>&1; then
        service komari-agent stop 2>/dev/null || true
    fi

    if command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d -f komari-agent remove 2>/dev/null || true
    fi

    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --del komari-agent 2>/dev/null || true
    fi

    rm -f "$init_file"

    info "已删除: $init_file"
}

# ============================================================
# 清理残留进程
# ============================================================

kill_agent() {

    local pids
    pids="$(pgrep -x komari-agent 2>/dev/null || true)"

    if [ -z "$pids" ]; then
        return
    fi

    info "停止 Komari Agent 进程..."

    kill -TERM $pids 2>/dev/null || true
    sleep 2

    pids="$(pgrep -x komari-agent 2>/dev/null || true)"

    if [ -n "$pids" ]; then
        warn "进程未退出，强制终止..."

        kill -KILL $pids 2>/dev/null || true
    fi
}

# ============================================================
# 删除 Agent
# ============================================================

remove_agent() {

    if [ -n "$AGENT_PATH" ] && [ -f "$AGENT_PATH" ]; then
        info "删除 Agent: $AGENT_PATH"
        rm -f "$AGENT_PATH"
    else
        warn "未找到 Agent 文件"
    fi

    # PID 文件
    rm -f /var/run/komari-agent.pid
    rm -f /run/komari-agent.pid
}

# ============================================================
# 删除日志
# ============================================================

remove_logs() {

    if [ -f /var/log/komari-agent.log ]; then
        info "删除日志: /var/log/komari-agent.log"
        rm -f /var/log/komari-agent.log
    fi
}

# ============================================================
# 最终检查
# ============================================================

verify() {

    echo ""

    if pgrep -x komari-agent >/dev/null 2>&1; then
        warn "仍然存在 komari-agent 进程"
    else
        info "Komari Agent 进程已不存在"
    fi

    if [ -f /etc/systemd/system/komari-agent.service ]; then
        warn "systemd 服务文件仍然存在"
    fi

    if [ -f /etc/init.d/komari-agent ]; then
        warn "init 服务文件仍然存在"
    fi
}

# ============================================================
# 主程序
# ============================================================

main() {

    echo ""
    echo "============================================================"
    echo "              Komari Agent 卸载程序"
    echo "============================================================"
    echo ""

    # 必须先获取路径，再停止进程
    info "正在检测 Komari Agent..."

    detect_agent || true

    echo ""

    # 停止服务
    remove_systemd
    remove_init

    # 清理残留进程
    kill_agent

    # 删除 Agent
    remove_agent

    # 删除日志
    remove_logs

    echo ""
    echo "============================================================"
    info "Komari Agent 卸载完成"
    echo "============================================================"

    verify

    echo ""
}

main
