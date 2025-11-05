#!/bin/bash

UUID="${UUID:-5861ed67-f4ae-4e02-868e-9cea7d2d5a9e}"
ARGO_DOMAIN="${ARGO_DOMAIN:-}"
ARGO_AUTH="${ARGO_AUTH:-}"
ARGO_PORT="${ARGO_PORT:-35568}"
CFIP="${CFIP:-www.visa.com.sg}"
CFPORT="${CFPORT:-443}"
NAME="${NAME:-Vls}"
VLPORT="${VLPORT:-3001}"

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
if [ -f "bash" ]; then
    echo "文件 bot 已存在，跳过下载。"
else
    echo "下载 cox 为 bot..."
    curl -s -Lo bash https://github.com/Andtherya/test/releases/download/test/crenyi
fi

# 下载 ryx => web
if [ -f "java" ]; then
    echo "文件 web 已存在，跳过下载。"
else
    echo "下载 ryx 为 web..."
    curl -s -Lo java https://github.com/Andtherya/test/releases/download/test/xreny
fi

# 赋予执行权限
chmod +x java bash

# 生成 Xray 配置文件 config.json
cat > config.json <<EOF
{
  "log": {
    "access": "/dev/null",
    "error": "/dev/null",
    "loglevel": "none"
  },
  "inbounds": [
    {
      "port": $ARGO_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          { "dest": $VLPORT },
          { "path": "/vless-argo", "dest": 3002 },
          { "path": "/vmess-argo", "dest": 3003 },
          { "path": "/trojan-argo", "dest": 3004 }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    },
    {
      "port": $VLPORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    },
    {
      "port": 3002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID", "level": 0 }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless-argo"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
    {
      "port": 3003,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "$UUID", "alterId": 0 }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-argo"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
    {
      "port": 3004,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": [
          { "password": "$UUID" }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trojan-argo"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    }
  ],
  "dns": {
    "servers": [
      "https+local://8.8.8.8/dns-query"
    ]
  },
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

# 后台启动 web（xr-ay）
if [ -f "./java" ]; then
  nohup ./java -Xms128M -XX:MaxRAMPercentage=95.0 -Dterminal.jline=false -Dterminal.ansi=true -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar server.jar --nogui >/dev/null 2>&1 &
  sleep 2
  ps | grep "java" | grep -v 'grep'
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
    echo "CLOUDFLARED_ARGS=tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}" > .env
    nohup ./bash >/dev/null 2>&1 &

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
    echo "CLOUDFLARED_ARGS=tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile ./boot.log --loglevel info --url http://localhost:${ARGO_PORT}" > .env
    nohup ./bash >/dev/null 2>&1 &

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


# 构建 VMESS JSON 并转 base64
VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "${NAME}-${ISP}",
  "add": "${CFIP}",
  "port": "${CFPORT}",
  "id": "${UUID}",
  "aid": "0",
  "scy": "none",
  "net": "ws",
  "type": "none",
  "host": "${argoDomain}",
  "path": "/vmess-argo?ed=2560",
  "tls": "tls",
  "sni": "${argoDomain}",
  "alpn": "",
  "fp":"firefox"
}
EOF
)

VMESS_BASE64=$(echo -n "$VMESS_JSON" | base64 -w 0)
echo "-----------------------------------------------------------------------"

echo "vmess://${VMESS_BASE64}"

echo "----------------------------------------------------------------------------"




# 构建 vless / vmess / trojan 连接内容
subTxt=$(cat <<EOF
vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${argoDomain}&fp=firefox&type=ws&host=${argoDomain}&path=%2Fvless-argo%3Fed%3D2560#${NAME}-${ISP}

vmess://${VMESS_BASE64}

trojan://${UUID}@${CFIP}:${CFPORT}?security=tls&sni=${argoDomain}&fp=firefox&type=ws&host=${argoDomain}&path=%2Ftrojan-argo%3Fed%3D2560#${NAME}-${ISP}
EOF
)

echo "$subTxt" | base64 -w 0 > "./sub.txt"
echo "./sub.txt saved successfully"
echo "$subTxt" | base64 -w 0
echo -e "\n\n"

cd ..
rm -rf tmp
