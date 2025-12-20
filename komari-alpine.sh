#!/bin/bash

# 使用默认值，如果未设置环境变量
KTOKEN="${KTOKEN:-}"
DOMAIN="${DOMAIN:-https://vldwvwjelrsl.cloud.cloudcat.one}"
WORKDIR=$(pwd)

if [ -z "${KTOKEN}" ]; then
    echo "Error: KTOKEN is not set or empty." >&2
    exit 1
fi

# 下载 komari-agent
if [ -f "komari-agent" ]; then
    echo "文件 komari-agent 已存在，跳过下载。"
else
    echo "下载 komari-agent..."
    curl -s -Lo komari-agent https://github.com/komari-monitor/komari-agent/releases/download/1.1.38/komari-agent-linux-amd64
    wait
    chmod +x komari-agent
fi

# === 生成 /etc/init.d/komari-agent ===
cat >/etc/init.d/komari-agent <<EOF
#!/sbin/openrc-run

description="komari Service"

command="${WORKDIR}/komari-agent"
command_args="-e ${DOMAIN} -t ${KTOKEN} --disable-auto-update"
command_user="root"
directory="${WORKDIR}"

command_background=yes
pidfile="/run/komari-agent.pid"

respawn_delay=5
respawn_max=0
EOF

chmod +x /etc/init.d/komari-agent
rc-update add komari-agent default
rc-service komari-agent restart
echo "✅ komari-agent服务已部署并启动完成！"


