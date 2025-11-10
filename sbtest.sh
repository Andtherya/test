#!/bin/bash

UUID="${UUID:-5861ed67-f4ae-4e02-868e-9cea7d2d5a9e}"
ARGO_DOMAIN="${ARGO_DOMAIN:-}"
ARGO_AUTH="${ARGO_AUTH:-}"
ARGO_PORT="${ARGO_PORT:-35568}"
CFIP="${CFIP:-www.visa.com.sg}"
CFPORT="${CFPORT:-443}"
NAME="${NAME:-Vls}"

pkill bot
pkill web

mkdir -p "./tmp"

cd ./tmp

# 检查并删除 boot.log
if [ -f "boot.log" ]; then
  rm -f "./boot.log"
  echo "已删除 ./boot.log"
fi

# 检查并删除 config.json
if [ -f "config.json" ]; then
  rm -f "./config.json"
  echo "已删除 ./config.json"
fi

# 检查并删除 sub.txt
if [ -f "sub.txt" ]; then
  rm -f "./sub.txt"
  echo "已删除 ./sub.txt"
fi


# 下载 cox => bot
if [ -f "bot" ]; then
    echo "文件 bot 已存在，跳过下载。"
else
    echo "下载 cox 为 bot..."
    curl -s -Lo bot https://github.com/Andtherya/test/releases/download/tjt/cloudflared-amd64
fi

# 下载 ryx => web
if [ -f "web" ]; then
    echo "文件 web 已存在，跳过下载。"
else
    echo "下载 ryx 为 web..."
    curl -s -Lo web https://github.com/Andtherya/test/releases/download/tjt/sing-box-amd64
fi

# 赋予执行权限
chmod +x bot web


cat > config.json <<EOF
{
    "log": {
      "disabled": true,
      "level": "error",
      "timestamp": true
    },
    "inbounds": [
    {
      "tag": "vmess-ws-in",
      "type": "vmess",
      "listen": "::",
      "listen_port": ${ARGO_PORT},
        "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/vmess-argo",
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "mtu": 1280,
      "address": [
        "172.16.0.2/32",
        "2606:4700:110:8dfe:d141:69bb:6b80:925/128"
      ],
      "private_key": "YFYOAdbw1bKTHlNNi+aEjBM3BO7unuFC5rOkMRAz9XY=",
      "peers": [
        {
          "address": "engage.cloudflareclient.com",
          "port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0",
            "::/0"
          ],
          "reserved": [
            78,
            135,
            76
          ]
        }
      ]
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rule_set": [
      {
        "tag": "youtube",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/youtube.srs",
        "download_detour": "direct"
      },
      {
        "tag": "netflix",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/netflix.srs",
        "download_detour": "direct"
      }
    ],
    "rules": [
      { "action": "sniff" },
      { "rule_set": ["youtube", "netflix"], "outbound": "warp-out" }
    ],
    "final": "direct"
  }
}
EOF

sleep 1

if [ -f "./web" ]; then
  nohup ./web run -c ./config.json >/dev/null 2>&1 &
  sleep 2
  ps | grep "web" | grep -v 'grep'
  echo "web 已启动。"
  echo "--------------------------------------------------"
else
  echo "启动失败：web 可执行文件不存在"
  exit 1
fi


# --- Cloudflare Tunnel 处理 ---
TUNNEL_MODE=""
FINAL_DOMAIN=""
TUNNEL_CONNECTED=false

# 检查是否使用固定隧道
if [ -n "$ARGO_AUTH" ] && [ -n "$ARGO_DOMAIN" ]; then
    TUNNEL_MODE="固定隧道 (Fixed Tunnel)"
    FINAL_DOMAIN="$ARGO_DOMAIN"
    echo "检测到 token 和 domain 环境变量，将使用【固定隧道模式】。"
    echo "隧道域名将是: $FINAL_DOMAIN"
    echo "Cloudflare Tunnel Token: [已隐藏]"
    echo "正在启动固定的 Cloudflare 隧道..."
    ARGS="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
    nohup ./bot $ARGS > ./boot.log 2>&1 &

    echo "正在等待 Cloudflare 固定隧道连接... (最多 30 秒)"
    for attempt in $(seq 1 15); do
        sleep 2
        if grep -q -E "Registered tunnel connection|Connected to .*, an Argo Tunnel an edge" ./boot.log; then
            TUNNEL_CONNECTED=true
            break
        fi
        echo -n "."
    done
    echo "bot 已启动"

else
    TUNNEL_MODE="临时隧道 (Temporary Tunnel)"
    echo "未提供 token 和/或 domain 环境变量，将使用【临时隧道模式】。"
    echo "正在启动临时的 Cloudflare 隧道..."
    ARGS="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile ./boot.log --loglevel info --url http://localhost:${ARGO_PORT}"
    nohup ./bot $ARGS >/dev/null 2>&1 &

    echo "正在等待 Cloudflare 临时隧道 URL... (最多 30 秒)"
    for attempt in $(seq 1 15); do
        sleep 2
        TEMP_TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare.com' ./boot.log | head -n 1)
        if [ -n "$TEMP_TUNNEL_URL" ]; then
            FINAL_DOMAIN=$(echo $TEMP_TUNNEL_URL | awk -F'//' '{print $2}')
            TUNNEL_CONNECTED=true
            break
        fi
        echo -n "."
    done
    echo ""
fi

# --- 输出结果 ---
if [ "$TUNNEL_CONNECTED" = "true" ]; then
    echo "--------------------------------------------------"
    echo "$TUNNEL_MODE 已成功连接！"
    echo "公共访问域名: $FINAL_DOMAIN"
    echo "--------------------------------------------------"
    echo ""
fi

argoDomain="$FINAL_DOMAIN"

# 获取 ISP 信息
metaInfo=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
ISP=$(echo "$metaInfo" | tr -d '\n')
path_encoded="%2F${UUID}%3Fed%3D2048"




# 构建 vless / vmess / trojan 连接内容
subTxt=$(cat <<EOF

vless://${UUID}@www.visa.com.tw:443?encryption=none&security=tls&sni=${FINAL_DOMAIN}&host=${FINAL_DOMAIN}&fp=chrome&type=ws&path=${path_encoded}#${ISP}-vls

EOF
)

echo "$subTxt" | base64 -w 0 > "./sub.txt"
echo "./sub.txt saved successfully"
echo "$subTxt" | base64 -w 0
