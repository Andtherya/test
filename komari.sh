#!/bin/bash
KTOKEN="${KTOKEN:-}"
DOMAIN="${DOMAIN:-https://vldwvwjelrsl.cloud.cloudcat.one}"
echo "${KTOKEN}\n"
echo "${DOMAIN}\n"
curl -Lo komari-agent https://github.com/komari-monitor/komari-agent/releases/download/1.1.34/komari-agent-linux-amd64
chmod +x komari-agent
nohup ./komari-agent -e $DOMAIN -t $TOKEN >/dev/null 2>&1 &

