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
    curl -s -Lo komari-agent https://github.com/komari-monitor/komari-agent/releases/download/1.1.38/komari-agent-linux-arm64
    wait
    chmod +x komari-agent
fi

cat >/etc/systemd/system/komari-agent.service <<'EOF'
[Unit]
Description=Komari Agent Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/default/komari-agent
WorkingDirectory=${WORKDIR}
ExecStart=${WORKDIR}/komari-agent -e ${DOMAIN} -t ${KTOKEN} --disable-auto-update

User=root
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable komari-agent
systemctl restart komari-agent
systemctl status komari-agent

