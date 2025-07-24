#!/bin/sh

# 环境变量，支持外部传入覆盖
UUID="${UUID:-5861ed67-f4ae-4e02-868e-9cea7d2d5a9e}"
ARGO_DOMAIN="${ARGO_DOMAIN:-}"
ARGO_AUTH="${ARGO_AUTH:-}"
ARGO_PORT="${ARGO_PORT:-35568}"
CFIP="${CFIP:-www.visa.com.sg}"
CFPORT="${CFPORT:-443}"
NAME="${NAME:-Vls}"

FILE_PATH="./tmp"
BOT="$FILE_PATH/bot"
WEB="$FILE_PATH/web"
BOOT_LOG="$FILE_PATH/boot.log"
TUNNEL_JSON="$FILE_PATH/tunnel.json"
TUNNEL_YML="$FILE_PATH/tunnel.yml"
SUB_PATH="$FILE_PATH/sub.txt"

mkdir -p "$FILE_PATH"
cd "$FILE_PATH" || exit 1

# 下载文件
[ ! -f "$BOT" ] && curl -Lo bot https://github.com/Kuthduse/glaxy/releases/download/test/cox
[ ! -f "$WEB" ] && curl -Lo web https://github.com/Kuthduse/glaxy/releases/download/test/ryx
chmod +x bot web

# 生成 config.json （保持不变）
cat > config.json <<EOF
{
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": [
    { "port": $ARGO_PORT, "protocol": "vless", "settings": { "clients": [ { "id": "$UUID", "flow": "xtls-rprx-vision" } ], "decryption": "none",
      "fallbacks": [
        { "dest": 3001 }, { "path": "/vless-argo", "dest": 3002 }, { "path": "/vmess-argo", "dest": 3003 }, { "path": "/trojan-argo", "dest": 3004 }
      ]
    }, "streamSettings": { "network": "tcp" } },
    { "port": 3001, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [ { "id": "$UUID" } ], "decryption": "none" }, "streamSettings": { "network": "tcp", "security": "none" } },
    { "port": 3002, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [ { "id": "$UUID", "level": 0 } ], "decryption": "none" },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vless-argo" } },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ], "metadataOnly": false }
    },
    { "port": 3003, "listen": "127.0.0.1", "protocol": "vmess", "settings": { "clients": [ { "id": "$UUID", "alterId": 0 } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess-argo" } },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ], "metadataOnly": false }
    },
    { "port": 3004, "listen": "127.0.0.1", "protocol": "trojan", "settings": { "clients": [ { "password": "$UUID" } ] },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/trojan-argo" } },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ], "metadataOnly": false }
    }
  ],
  "dns": { "servers": [ "https+local://8.8.8.8/dns-query" ] },
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ]
}
EOF

# 生成固定隧道配置（仅当 ARGO_AUTH 和 ARGO_DOMAIN 都有且 ARGO_AUTH 包含 TunnelSecret）
if [ -n "$ARGO_AUTH" ] && [ -n "$ARGO_DOMAIN" ] && echo "$ARGO_AUTH" | grep -q "TunnelSecret"; then
  echo "$ARGO_AUTH" > "$TUNNEL_JSON"
  TUNNEL_ID=$(echo "$ARGO_AUTH" | awk -F'"' '{print $12}')
  cat > "$TUNNEL_YML" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_JSON
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$ARGO_PORT
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
fi

# 启动 web 服务
if [ -f "$WEB" ]; then
  nohup "$WEB" -c config.json >/dev/null 2>&1 &
  echo "web 已启动"
  sleep 1
else
  echo "web 文件不存在"
  exit 1
fi

# 启动 bot 服务函数
start_bot() {
  if [ ! -f "$BOT" ]; then
    echo "bot 文件不存在，无法启动"
    return 1
  fi

  if [ -n "$ARGO_AUTH" ] && [ -n "$ARGO_DOMAIN" ]; then
    # 两者均不为空，启动固定隧道
    if echo "$ARGO_AUTH" | grep -q "TunnelSecret"; then
      echo "启动固定隧道（TunnelSecret）"
      nohup "$BOT" tunnel --edge-ip-version auto --config "$TUNNEL_YML" run >/dev/null 2>&1 &
    elif echo "$ARGO_AUTH" | grep -Eq '^[A-Za-z0-9=]{120,250}$'; then
      echo "启动固定隧道（Token）"
      nohup "$BOT" tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token "$ARGO_AUTH" >/dev/null 2>&1 &
    else
      echo "ARGO_AUTH 格式异常，启动快速隧道"
      nohup "$BOT" tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile "$BOOT_LOG" --loglevel info --url http://localhost:"$ARGO_PORT" >/dev/null 2>&1 &
    fi
  else
    # 任意为空，启动临时隧道
    echo "ARGO_AUTH 或 ARGO_DOMAIN 为空，启动临时隧道"
    nohup "$BOT" tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile "$BOOT_LOG" --loglevel info --url http://localhost:"$ARGO_PORT" >/dev/null 2>&1 &
  fi
}

# 生成订阅文件
generate_sub_base64() {
  argo_domain="$1"
  echo "生成订阅文件，域名：$argo_domain"
  metaInfo=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
  ISP=$(echo "$metaInfo" | tr -d '\r\n')
  VMESS_JSON=$(printf '{"v":"2","ps":"%s-%s","add":"%s","port":"%s","id":"%s","aid":"0","scy":"none","net":"ws","type":"none","host":"%s","path":"/vmess-argo?ed=2560","tls":"tls","sni":"%s","alpn":""}' \
    "$NAME" "$ISP" "$CFIP" "$CFPORT" "$UUID" "$argo_domain" "$argo_domain")
  VMESS_B64=$(echo -n "$VMESS_JSON" | base64 -w 0)
  subTxt=$(cat <<EOF
vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${argo_domain}&type=ws&host=${argo_domain}&path=%2Fvless-argo%3Fed%3D2560#${NAME}-${ISP}

vmess://${VMESS_B64}

trojan://${UUID}@${CFIP}:${CFPORT}?security=tls&sni=${argo_domain}&type=ws&host=${argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#${NAME}-${ISP}
EOF
)
  echo "$subTxt" | base64 -w 0 > "$SUB_PATH"
  echo "订阅文件写入 $SUB_PATH"
  echo "订阅内容（base64）:"
  cat "$SUB_PATH"
}

# 提取 Argo 域名并生成订阅，支持重试
extract_domains_and_generate_sub() {
  # 优先用环境变量
  if [ -n "$ARGO_DOMAIN" ]; then
    generate_sub_base64 "$ARGO_DOMAIN"
    return 0
  fi

  # 从日志提取
  if [ ! -f "$BOOT_LOG" ]; then
    echo "$BOOT_LOG 不存在，无法提取域名"
    return 1
  fi

  argo_domains=$(grep -oE 'https?://[^ ]*trycloudflare\.com/?' "$BOOT_LOG" | sed -E 's#https?://([^/]+)/?#\1#')
  if [ -n "$argo_domains" ]; then
    argo_domain=$(echo "$argo_domains" | head -n1)
    echo "提取到 ArgoDomain: $argo_domain"
    generate_sub_base64 "$argo_domain"
  else
    echo "未找到 ArgoDomain，尝试重启 bot 并重试"
    rm -f "$BOOT_LOG"
    pkill -f "[b]ot" >/dev/null 2>&1 || true
    sleep 3
    start_bot
    sleep 3
    extract_domains_and_generate_sub
  fi
}

# 启动 bot，生成订阅
start_bot
sleep 5
extract_domains_and_generate_sub

echo "脚本执行完成"
