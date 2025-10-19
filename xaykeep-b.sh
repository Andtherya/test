#!/bin/bash
# 一键部署 systemd 服务：bot + web
# 适用于 Debian / Ubuntu / CentOS / Rocky / Arch 等 systemd 系统

set -e

# === 配置区 ===
ARGO_AUTH="${ARGO_AUTH:-}"           # Cloudflare Argo Tunnel token
WORKDIR="${WORKDIR:-/root/tmp}"      # 工作目录
BOT_BIN="${WORKDIR}/bot"
WEB_BIN="${WORKDIR}/web"
WEB_CONF="${WORKDIR}/config.json"

pkill web
pkill bot

# === 检查依赖 ===
if ! command -v systemctl >/dev/null 2>&1; then
  echo "❌ 当前系统不支持 systemd，无法使用本脚本。"
  exit 1
fi

if [[ -z "$ARGO_AUTH" ]]; then
  echo "⚠️  未设置 ARGO_AUTH 环境变量，请先执行："
  echo "    export ARGO_AUTH=<你的token>"
  exit 1
fi

if [[ ! -x "$BOT_BIN" || ! -x "$WEB_BIN" ]]; then
  echo "⚠️  找不到可执行文件：$BOT_BIN 或 $WEB_BIN"
  exit 1
fi

# === 停止旧服务 ===
systemctl stop bot.service 2>/dev/null || true
systemctl stop web.service 2>/dev/null || true

# === 生成 web.service ===
cat >/etc/systemd/system/web.service <<EOF
[Unit]
Description=Web Service
After=network.target

[Service]
WorkingDirectory=${WORKDIR}
ExecStart=${WEB_BIN} -c ${WEB_CONF}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# === 生成 bot.service ===
cat >/etc/systemd/system/bot.service <<EOF
[Unit]
Description=Bot Service
After=web.service

[Service]
WorkingDirectory=${WORKDIR}
ExecStart=${BOT_BIN} tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# === 重新加载 systemd 配置 ===
systemctl daemon-reload

# === 启用并启动服务 ===
systemctl enable web.service bot.service
systemctl restart web.service
systemctl restart bot.service

# === 打印状态 ===
sleep 2
systemctl is-active --quiet web && echo "✅ Web 服务已启动"
systemctl is-active --quiet bot && echo "✅ Bot 服务已启动"

echo "🎉 部署完成！服务已设置为开机自启。"
