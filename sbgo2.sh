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
    curl -Lo bot https://github.com/Andtherya/cloudflaredtest/releases/download/6/cloudflared-linux-amd64
fi

# 下载 ryx => web
if [ -f "web" ]; then
    echo "文件 web 已存在，跳过下载。"
else
    echo "下载 ryx 为 web..."
    curl -Lo web https://github.com/Andtherya/sing-box000/releases/download/3/sing-box-linux-amd64
fi

# 赋予执行权限
chmod +x bot web

# 生成 Xray 配置文件 config.json
cat > config.json <<EOF
{
  "log": { "disabled": false, "level": "info", "timestamp": true },
  "inbounds": [
    { "type": "vless", "tag": "proxy", "listen": "::", "listen_port": $ARGO_PORT,
      "users": [ { "uuid": "${UUID}", "flow": "" } ],
      "transport": { "type": "ws", "path": "/${UUID}", "max_early_data": 2048, "early_data_header_name": "Sec-WebSocket-Protocol" }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "direct"
  }

}
EOF

# 后台启动 web（xr-ay）
if [ -f "./web" ]; then
  nohup ./web >/dev/null 2>&1 &
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

# 编码 subTxt 并写入 sub.txt
echo "$subTxt" | base64 > "./sub.txt"
echo "./sub.txt saved successfully"

# 输出 base64 结果（可用于 curl 返回）
echo "$subTxt" | base64
