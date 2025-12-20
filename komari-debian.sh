#!/bin/bash

# 使用默认值，如果未设置环境变量
KTOKEN="${KTOKEN:-}"
DOMAIN="${DOMAIN:-https://vldwvwjelrsl.cloud.cloudcat.one}"
WORKDIR=$(pwd)
BIN_NAME="komari-agent"
SERVICE_NAME="komari-agent"

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

# ===== 写入环境变量文件 =====
echo "🧾 写入 /etc/default/${SERVICE_NAME} ..."
cat >/etc/default/${SERVICE_NAME} <<EOF
WORKDIR=${WORKDIR}
DOMAIN=${DOMAIN}
KTOKEN=${KTOKEN}
EOF

chmod 600 /etc/default/${SERVICE_NAME}

# ===== 创建 systemd service =====
echo "⚙️ 创建 systemd service ..."
cat >/etc/systemd/system/${SERVICE_NAME}.service <<'EOF'
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

# ===== 重新加载并启动 =====
echo "🔄 重新加载 systemd..."
systemctl daemon-reexec
systemctl daemon-reload

echo "🚀 启动 komari-agent..."
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

# ===== 状态检查 =====
sleep 1
echo "📊 服务状态："
systemctl --no-pager --full status ${SERVICE_NAME}

echo "✅ komari-agent 服务已在 Debian 上部署并启动完成！"
echo "👉 日志查看：journalctl -u ${SERVICE_NAME} -f"
