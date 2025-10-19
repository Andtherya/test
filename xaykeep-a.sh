#!/bin/bash
# 一键部署 OpenRC 服务：bot + web

pkill bot
pkill web

# === 配置区 ===
ARGO_AUTH="${ARGO_AUTH:-}"
WORKDIR="${WORKDIR:-/root/tmp}"

# === 生成 /etc/init.d/bot ===
cat >/etc/init.d/bot <<EOF
#!/sbin/openrc-run

description="My Bot Service"

command="${WORKDIR}/bot"
command_args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
command_user="root"
directory="${WORKDIR}"

command_background=yes
pidfile="/run/bot.pid"

respawn_delay=5
respawn_max=0
EOF

# === 生成 /etc/init.d/web ===
cat >/etc/init.d/web <<EOF
#!/sbin/openrc-run

description="My Web Service"

command="${WORKDIR}/web"
command_args="run -c config.json"
command_user="root"
directory="${WORKDIR}"

command_background=yes
pidfile="/run/web.pid"

respawn_delay=5
respawn_max=0
EOF

# === 赋权并添加服务 ===
chmod +x /etc/init.d/web
chmod +x /etc/init.d/bot

rc-update add web default
rc-update add bot default

# === 启动服务 ===
rc-service web restart
rc-service bot restart

echo "✅ bot 与 web 服务已部署并启动完成！"
