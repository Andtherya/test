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

cat >/etc/systemd/system/komari-agent.service <<EOF
[Unit]
Description=komari-agent service
After=komari-agent.service

[Service]
WorkingDirectory=${WORKDIR}
ExecStart=${WORKDIR}/komari-agent -e ${DOMAIN} -t ${KTOKEN} --disable-auto-update
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable komari-agent
sudo systemctl restart komari-agent

