#!/bin/bash

export AGENT_TOKEN="${AGENT_TOKEN:-}"
export AGENT_ENDPOINT="${AGENT_ENDPOINT:-}"
export AGENT_DISABLE_AUTO_UPDATE="${AGENT_DISABLE_AUTO_UPDATE:-true}"

pkill komari-agent

curl -s -Lo komari-agent https://github.com/komari-monitor/komari-agent/releases/download/1.1.38/komari-agent-linux-amd64
wait

chmod +x komari-agent
nohup ./komari-agent >/dev/null 2>&1 &

sleep 2

rm komari-agent

echo -e "Done.\n"
