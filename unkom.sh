#!/usr/bin/env bash

set -e

echo "[*] Stopping komari-agent..."

# 停止服务
systemctl stop komari-agent 2>/dev/null || true
rc-service komari-agent stop 2>/dev/null || true
service komari-agent stop 2>/dev/null || true

echo "[*] Disabling startup..."

# 禁用开机启动
systemctl disable komari-agent 2>/dev/null || true
rc-update del komari-agent 2>/dev/null || true
update-rc.d -f komari-agent remove 2>/dev/null || true
chkconfig --del komari-agent 2>/dev/null || true

echo "[*] Killing processes..."

# 杀进程
pkill -9 -f komari-agent 2>/dev/null || true

echo "[*] Removing service files..."

# 删除 service
rm -f /etc/systemd/system/komari-agent.service
rm -f /usr/lib/systemd/system/komari-agent.service
rm -f /etc/init.d/komari-agent

echo "[*] Reloading daemon..."

# 刷新 systemd
systemctl daemon-reload 2>/dev/null || true
systemctl reset-failed 2>/dev/null || true

echo "[*] Removing logs..."

# 删除日志
rm -f /var/log/komari-agent.log

echo "[*] Searching for binary..."

# 删除常见目录
rm -f ./komari-agent
rm -f /usr/local/bin/komari-agent
rm -f /usr/bin/komari-agent

# 删除可能工作目录
find /opt /root /home /usr/local -type f -name "komari-agent" 2>/dev/null -exec rm -f {} \;

echo "[*] Checking remaining processes..."

if pgrep -f komari-agent >/dev/null; then
    echo "[!] Still running:"
    pgrep -af komari-agent
else
    echo "[+] komari-agent fully removed."
fi
