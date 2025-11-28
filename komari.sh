#!/bin/bash

token="${KTOKEN:-}"
domain="${DOMAIN:-https://vldwvwjelrsl.cloud.cloudcat.one}"
echo "${token}"
curl -Lo komari-agent https://github.com/komari-monitor/komari-agent/releases/download/1.1.34/komari-agent-linux-amd64
chmod +x komari-agent
nohup ./komari-agent  -e $domain -t $token >/dev/null 2>&1 &

