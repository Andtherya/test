#!/bin/bash

# 使用默认值，如果未设置环境变量
KTOKEN="${KTOKEN:-}"
DOMAIN="${DOMAIN:-https://vldwvwjelrsl.cloud.cloudcat.one}"

# 下载 komari-agent
curl -s -Lo komari-agent https://github.com/komari-monitor/komari-agent/releases/download/1.1.34/komari-agent-linux-amd64

await

# 给脚本文件添加可执行权限
chmod +x komari-agent

# 后台运行 komari-agent，确保传递的是 $KTOKEN 而不是 $TOKEN
nohup ./komari-agent -e "$DOMAIN" -t "$KTOKEN" >/dev/null 2>&1 &

sleep 2

rm komari-agent

echo -e "Done.\n"
